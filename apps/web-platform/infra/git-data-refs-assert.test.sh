#!/usr/bin/env bash
#
# git-data-refs-assert.sh and the MODE=refs_assert verb of git-data-cutover.sh (#11431, epic #8211;
# plan knowledge-base/project/plans/2026-10-29-feat-git-data-cutover-refs-assert-plan.md).
#
# TWO TIERS.
#   A  HOST SCRIPT. The REAL git-data-refs-assert.sh, fed the way production feeds it (`bash -s < file`),
#      over REAL `git` bare-repository fixtures. Every system read the script makes goes through an EXTERNAL
#      command (readlink, stat, find, mktemp, runuser, rm), and those are PATH shims that map the store root
#      /mnt/git-data onto a per-row world directory. The script carries no test seam (ADR-214). The runuser
#      shim accepts EXACTLY the modeled argv (env -i, the hardening flags, the one for-each-ref and its
#      format) and refuses any other with a logged violation, so a write verb or a changed flag set is RED. EVERY verb
#      the shim dispatcher names is symlinked into the shim directory (an anchor row derives the list from the
#      dispatcher itself), and static censuses pin the closed command set, the redirect set and the exit paths of the
#      script, so a write the shims do not model is still RED.
#   B  VERB. git-data-cutover.sh MODE=refs_assert against an `ssh` shim: the script body on stdin, the
#      %q-quoted input, the 60 s bound, every rc -> verdict word and class, off-shape answers refused,
#      runner-side refusals, and one end-to-end row where the ssh shim runs the body through a real
#      `bash -s` over the tier-A world.
#
# FIXTURES are synthesized (cq-test-fixtures-synthesized-only): every repository, worktree and branch name
# is made up, long and unique, and a print scan over EVERY row proves none of them reaches stdout, stderr,
# the step summary or GITHUB_OUTPUT (the only 40-hex strings allowed are inside the matched shas= field).
#
# Run: bash apps/web-platform/infra/git-data-refs-assert.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh derives it).
set -uo pipefail
export LC_ALL=C
ulimit -c 0 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SCRIPT="$DIR/git-data-refs-assert.sh"
CUTOVER="$DIR/git-data-cutover.sh"
WF="$ROOT/.github/workflows/git-data-cutover.yml"
RUNBOOK="$ROOT/knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md"
USERDATA_TF="$DIR/modules/git-data-userdata/main.tf"

pass=0
fail=0
executed=0
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1"; }

# INSTRUMENT SELF-TEST: drive both counters once each and refuse to continue unless both moved.
_p0=$pass; _f0=$fail
ok "instrument self-test (expected)" >/dev/null
no "instrument self-test (expected)" >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ]; then
  echo "FATAL: instrument self-test did not move both counters" >&2; exit 2
fi
pass=$_p0; fail=$_f0; executed=0

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
instrument() { echo "INSTRUMENT: $*" >&2; exit 2; }

[ -f "$CUTOVER" ] || instrument "missing $CUTOVER"
for b in git python3 awk sed find cmp timeout mktemp readlink stat sort; do
  command -v "$b" >/dev/null 2>&1 || instrument "required binary '$b' not found on PATH"
done
REALGIT="$(command -v git)"
[ "$REALGIT" = /usr/bin/git ] || instrument "git is not /usr/bin/git ($REALGIT): the modeled argv names /usr/bin/git"

T="$(mktemp -d "${TMPDIR:-/var/tmp}/gd-refs-assert.XXXXXXXX")" || instrument "mktemp -d failed"
assert_fixture_dir "$T"
cleanup() { rm -rf "$T"; return 0; }
trap cleanup EXIT
# Hermetic git: no ambient config, fixed identity and dates, HOME and TMPDIR under the scratch directory.
export HOME="$T/home" TMPDIR="$T/tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.invalid GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.invalid
export GIT_AUTHOR_DATE='2001-01-01T00:00:00Z' GIT_COMMITTER_DATE='2001-01-01T00:00:00Z'
mkdir -p "$HOME" "$TMPDIR" || instrument "mkdir home failed"

# ══════════════════════════════════════════════════════════════════════════════════════════
# Synthesized identifiers. Long and unique, mixing . _ - and digits; they must never be printed.
# ══════════════════════════════════════════════════════════════════════════════════════════
WT_A='wt-7f3a.k_91x'
WT_B='wt-b04d.q_55z'
BR_A='br-3e9a.work_01'
BR_B='feat-2c7d/x.y_9'
BR_C='br-91ce_zz.7'
REPO_BASE='ws-7f3a91c2.acme_corp-01'
REPO="$REPO_BASE.git"
REPO2='ws-b04d55e1.globex_lab-02.git'
REPO_HOSTILE='::error::pwn-4d2e.git'
REPO_PLAIN='ws-plain_4410'
REPO_LINK='ws-link_9921.git'
SCAN_IDS=("$WT_A" "$WT_B" "$BR_A" "$BR_B" "$BR_C" "$REPO_BASE" "$REPO2" "$REPO_HOSTILE" "$REPO_PLAIN" "$REPO_LINK")

# ── the template repository: objects only, no refs ───────────────────────────────────────
TPL="$T/tpl.git"
git init -q --bare "$TPL" || instrument "git init tpl failed"
g() { git --git-dir="$TPL" "$@"; }
EMPTY_TREE="$(g hash-object -t tree -w /dev/null)"
C1="$(GIT_AUTHOR_DATE='2001-01-01T00:00:01Z' GIT_COMMITTER_DATE='2001-01-01T00:00:01Z' g commit-tree "$EMPTY_TREE" -m c1)"
C2="$(GIT_AUTHOR_DATE='2001-01-01T00:00:02Z' GIT_COMMITTER_DATE='2001-01-01T00:00:02Z' g commit-tree "$EMPTY_TREE" -p "$C1" -m c2)"
C3="$(GIT_AUTHOR_DATE='2001-01-01T00:00:03Z' GIT_COMMITTER_DATE='2001-01-01T00:00:03Z' g commit-tree "$EMPTY_TREE" -p "$C2" -m c3)"
BLOB="$(printf 'fixture\n' | g hash-object -w --stdin)"
TREE2="$(printf '100644 blob %s\tf\n' "$BLOB" | g mktree)"
TAG_C="$(printf 'object %s\ntype commit\ntag t1\ntagger fx <fx@example.invalid> 978307200 +0000\n\nmsg\n' "$C1" | g hash-object -t tag -w --stdin)"
TAG_T="$(printf 'object %s\ntype tree\ntag t2\ntagger fx <fx@example.invalid> 978307200 +0000\n\nmsg\n' "$TREE2" | g hash-object -t tag -w --stdin)"
for v in EMPTY_TREE C1 C2 C3 BLOB TREE2 TAG_C TAG_T; do
  [[ "${!v}" =~ ^[0-9a-f]{40}$ ]] || instrument "template object $v is not a 40-hex id: ${!v}"
done
# The sha order the printed field must follow (numeric/lexicographic over lowercase hex), computed, never typed.
mapfile -t SORTED3 < <(printf '%s\n' "$C1" "$C2" "$C3" | sort)

# ══════════════════════════════════════════════════════════════════════════════════════════
# Tier A — the world and the shims
# ══════════════════════════════════════════════════════════════════════════════════════════
SH="$T/shim"; assert_fixture_dir "$SH"; mkdir -p "$SH" || instrument "mkdir shim failed"
# The write verbs of Guard 2 mutation 2. PATH_VERBS get a failing shim; the git verbs are refused by the
# runuser shim's exact-argv rule. An anchor row derives the dispatcher's verb list FROM THE DISPATCHER and asserts it
# equals the symlinked set (no dead arm), and that the mutation list below is a subset of it.
WRITE_VERBS_PATH="rm chown mount systemctl touch mkdir"
WRITE_VERBS_GIT="gc update-ref"
cat > "$SH/_shim" <<'SHIM'
#!/usr/bin/env bash
# One dispatcher, many names. $WORLD describes the simulated host; the shim's own directory is stripped from
# PATH before anything is delegated, so the delegate is the REAL tool. /mnt/git-data is the store root the
# script hardcodes; it is mapped onto $WORLD/store for every operand and mapped back in every answer.
n="${0##*/}"
SD="${0%/*}"
PATH="${PATH#"$SD":}"
W="${WORLD:?}"
ST="$W/state"
MNT=/mnt/git-data
flag() { [ -e "$W/$1" ]; }
viol() { printf '%s\t%s\n' "$n" "$*" >> "$ST/violations"; }
mapargs() { MA=(); local a; for a in "$@"; do MA+=("${a//$MNT/$W/store}"); done; }
unmap() { local s; while IFS= read -r s || [ -n "$s" ]; do printf '%s\n' "${s//$W\/store/$MNT}"; done; }
case "$n" in
  rm|rmdir)
    # the script may remove ONLY the scratch directory it made (the mktemp shim records it)
    for a in "$@"; do
      case "$a" in -*) continue ;; esac
      grep -qxF -- "${a%/*}" "$ST/shm_dirs" 2>/dev/null || grep -qxF -- "$a" "$ST/shm_dirs" 2>/dev/null || { viol "$n $*"; exit 99; }
    done
    if flag noisy; then printf 'noise %s\n' "$(cat "$W/noisy")"; printf 'noise %s\n' "$(cat "$W/noisy")" >&2; fi
    exec "$n" "$@" ;;
  chown|mount|umount|systemctl|kill|chmod|touch|mv|cp|ln|truncate|tee|mkdir|install|dd|mkfifo|mknod|git)
    viol "$n $*"; exit 99 ;;
  mktemp)
    flag noisy && printf 'noise %s\n' "$(cat "$W/noisy")" >&2
    mkdir -p "$W/shm" || exit 1
    d="$(mktemp -d -p "$W/shm")" || exit 1
    printf '%s\n' "$d" >> "$ST/shm_dirs"
    printf '%s\n' "$*" >> "$ST/mktemp_argv"
    printf '%s\n' "$d"; exit 0 ;;
  sort)
    if flag sort_trunc; then "$n" "$@" | sed '$d'; exit 0; fi
    exec "$n" "$@" ;;
  readlink)
    printf '%s\n' "$*" >> "$ST/readlink_argv"
    flag noisy && printf 'noise %s\n' "$(cat "$W/noisy")" >&2
    mapargs "$@"; "$n" "${MA[@]}" | unmap; exit "${PIPESTATUS[0]}" ;;
  stat)
    printf '%s\n' "$*" >> "$ST/stat_argv"
    flag noisy && printf 'noise %s\n' "$(cat "$W/noisy")" >&2
    # stat_fail_at <k>: the k-th stat call of the run fails (every `|| die 16 stat_failed` site is reachable)
    if [ -f "$W/stat_fail_at" ] && [ "$(wc -l < "$ST/stat_argv")" = "$(cat "$W/stat_fail_at")" ]; then exit 1; fi
    fmt=""; prev=""; for a in "$@"; do [ "$prev" = "-c" ] && fmt="$a"; prev="$a"; done
    mapargs "$@"
    if [ "$fmt" = '%d:%i:%F:%U' ]; then
      # the fixture's owner is the test user, not the host's git account: model the owner as a flag (real stat otherwise)
      out="$("$n" -c '%d:%i:%F' "${MA[@]:2}")" || exit $?
      # owner_flip: the owner changes AFTER the read (the runuser shim has logged a call), the re-check must notice
      if flag owner_foreign || { flag owner_flip && [ -s "$ST/runuser_calls" ]; }; then echo "$out:root"; else echo "$out:git"; fi
      exit 0
    fi
    if [ "$fmt" = "%m" ]; then
      "$n" "${MA[@]}" > /dev/null || exit $?
      if flag not_on_mount; then echo /; else echo "$MNT"; fi
      exit 0
    fi
    if flag stat_fail; then exit 1; fi
    exec "$n" "${MA[@]}" ;;
  find)
    printf '%s\n' "$*" >> "$ST/find_argv"
    flag noisy && printf 'noise %s\n' "$(cat "$W/noisy")" >&2
    mapargs "$@"
    if flag find_fail; then "$n" "${MA[@]}"; exit 3; fi
    case " $* " in *" -name shallow "*) flag find_fail_shallow && exit 3 ;; esac
    case " $* " in *" -printf a "*) flag find_fail_shape && exit 3 ;; esac
    exec "$n" "${MA[@]}" ;;
  runuser)
    printf '%s\n' "$*" >> "$ST/runuser_calls"
    # the answer fds must be closed for the git child (the script passes 3>&- 4>&-)
    if [ -e /proc/$$/fd/3 ] || [ -e /proc/$$/fd/4 ]; then viol "fd-leak $*"; fi
    REPO_ARG=""
    for a in "$@"; do case "$a" in --git-dir=*) REPO_ARG="${a#--git-dir=}" ;; esac; done
    FMT='%(refname)%09%(objectname)%09%(objecttype)%09<%(*objecttype)>%09<%(symref)>'
    want="-u git -- /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat /usr/bin/git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat --git-dir=$REPO_ARG for-each-ref --count=201 --format=$FMT refs/soleur/worktrees/"
    if [ "$*" != "$want" ] || [ "${REPO_ARG#"$MNT"/repositories/}" = "$REPO_ARG" ]; then
      printf '%s\n' "$*" >> "$ST/bad_argv"; echo "fatal: bad argv" >&2; exit 64
    fi
    if flag runuser_stdin; then cat > "$W/state/runuser_stdin_bytes"; fi
    if flag term_self; then
      # signal the script itself (the nearest ancestor running `bash -s`), then carry on: its trap must turn the signal into rc 16
      # (the HIGHEST such ancestor: the command substitution's subshell has the same command line)
      p=$$; top=""; while [ "$p" -gt 1 ]; do
        if [ "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" = "bash -s " ]; then top="$p"; fi
        p="$(awk '/^PPid:/ {print $2}' "/proc/$p/status")"
      done
      [ -z "$top" ] || kill -TERM "$top"
      sleep 1
    fi
    if flag git_missing_object; then echo "fatal: missing object 0000000000000000000000000000000000000000 for refs/x" >&2; exit 128; fi
    if flag git_fake_out; then
      cat "$W/git_fake_out"
      if [ -f "$W/git_fake_err" ]; then cat "$W/git_fake_err" >&2; fi
      exit "$(cat "$W/git_fake_rc" 2>/dev/null || echo 0)"
    fi
    real="$W/store/${REPO_ARG#"$MNT"/}"
    "$REALGIT" -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat --git-dir="$real" for-each-ref --count=201 --format="$FMT" refs/soleur/worktrees/
    rc=$?
    if flag toctou_swap_repos; then
      # a NEW repositories directory (new inode) around the SAME repository directory: only the directory identity changes
      r="$W/store/repositories"; mkdir "$r.new" && mv "$r/${REPO_ARG##*/}" "$r.new/" && mv "$r" "$r.old" && mv "$r.new" "$r" && rm -rf "$r.old"
    fi
    if flag toctou_swap; then
      # replace the repository directory by a copy (new inode) AFTER the read: the script's second stat must differ
      cp -a "$real" "$real.swap" && rm -rf "$real" && mv "$real.swap" "$real"
    fi
    exit "$rc" ;;
  *) echo "unshimmed $n" >&2; exit 98 ;;
esac
SHIM
chmod +x "$SH/_shim" || instrument "chmod shim failed"
# EVERY verb the dispatcher names is linked (an arm that is never linked is a dead guard); the list is derived from the
# dispatcher's own case arms, not typed a second time.
SHIM_VERBS="$(awk '/^case "\$n" in$/ {on=1; next} /^esac$/ {on=0} on && /^  [a-z|]+\)/ {gsub(/^  /,""); sub(/\).*$/,""); gsub(/\|/," "); print}' "$SH/_shim" | tr '\n' ' ')"
for _v in $SHIM_VERBS; do [ "$_v" = "*" ] || ln -sf _shim "$SH/$_v" || instrument "ln shim $_v failed"; done
# The shim body calls rm/mv/cp for its own bookkeeping through the real tools: keep real copies reachable.
export REALGIT

W=""
new_world() { # <label> — a fresh simulated host; sets W
  W="$T/w-$1"; assert_fixture_dir "$W"
  rm -rf "$W"; mkdir -p "$W/store/repositories" "$W/state" "$W/shm" "$W/home" || instrument "mkdir world $1 failed"
  : > "$W/state/violations"
}
mkrepo() { cp -a "$TPL" "$W/store/repositories/$1" || instrument "mkrepo $1 failed"; }
mkbare() { git init -q --bare "$W/store/repositories/$1" || instrument "git init $1 failed"; }
wref() { git --git-dir="$W/store/repositories/$1" update-ref "$2" "$3" || instrument "update-ref $2 failed"; }
nsref() { printf 'refs/soleur/worktrees/%s/%s' "$1" "$2"; }
# fixture switch used by the "break the suite" harness row: the builder creates no refs
FIXTURE_NO_REFS=0
want_ref() { [ "$FIXTURE_NO_REFS" = 1 ] || wref "$@"; }

HS="$SCRIPT"
HRC=0; HOUT=""; HERR=""
SCAN_FAILS=()
SCAN_RUNS=0
SCAN_ON=1   # off while the mutation matrix runs (a mutant legitimately prints what the real script never would)
# scan_files <file...> — 0 clean; 1 an identifier or a stray 40-hex string; 2 the instrument is broken
scan_files() {
  [ "${#SCAN_IDS[@]}" -gt 0 ] || return 2
  local f id leak=0 hexline
  for f in "$@"; do
    [ -e "$f" ] || continue
    for id in "${SCAN_IDS[@]}"; do
      [ -n "$id" ] || return 2
      if grep -qF -- "$id" "$f"; then leak=1; fi
    done
    # the only 40-hex strings allowed are inside the matched shas= field of the one answer line
    hexline="$(grep -E '[0-9a-f]{40}' "$f" | grep -vE '^(\[git-data-cutover\] REFS_ASSERT |- REFS_ASSERT |ok )?(refs_assert )?ok repos=1 namespaces=[1-9][0-9]* refs=[1-9][0-9]* heads=[1-9][0-9]* shas=[0-9a-f]{40}(,[0-9a-f]{40})?$' | grep -vE '^refs_assert ok ' || true)"
    [ -z "$hexline" ] || leak=1
  done
  return "$leak"
}
# assert_clean <row> <file...> — records a failure NAMED by its row (the print scan of every run)
assert_clean() {
  local row="$1"; shift
  [ "$SCAN_ON" = 1 ] || return 0
  SCAN_RUNS=$((SCAN_RUNS + 1))
  local rc=0; scan_files "$@" || rc=$?
  [ "$rc" = 0 ] || SCAN_FAILS+=("$row(rc=$rc)")
}

# run_host <row> [VAR=value ...] — the REAL script, stdin from a file, over the current world
run_host() {
  local row="$1"; shift
  HOUT="$W/out"; HERR="$W/err"
  : > "$W/state/runuser_calls"; : > "$HOUT"; : > "$HERR"
  HRC=0
  env -i PATH="$SH:/usr/bin:/bin" HOME="$W/home" WORLD="$W" REALGIT="$REALGIT" \
    REFS_REPOS=/mnt/git-data/repositories "$@" bash -s < <(cat "$HS") > "$HOUT" 2> "$HERR" || HRC=$?
  assert_clean "$row" "$HOUT" "$HERR"
}
# shm_clean — every scratch directory the mktemp shim handed out is gone again (the EXIT trap ran its cleanup)
shm_clean() { local d; [ -s "$W/state/shm_dirs" ] || return 0; while IFS= read -r d; do [ ! -e "$d" ] || return 1; done < "$W/state/shm_dirs"; return 0; }
violations() { [ ! -s "$W/state/violations" ] && [ ! -s "$W/state/bad_argv" ] && shm_clean; }
runuser_n() { wc -l < "$W/state/runuser_calls"; }
# host_is <rc> <reason-line-or-""> <stdout> — the WHOLE stdout and stderr, never a substring
host_is() {
  [ "$HRC" = "$1" ] && [ "$(cat "$HOUT")" = "$3" ] && [ "$(cat "$HERR")" = "$2" ] && violations
}
ANS() { printf 'refs_assert ok repos=1 namespaces=%s refs=%s heads=%s shas=%s' "$1" "$2" "$3" "$4"; }
ERRL() { printf 'refs-assert: rc=%s reason=%s' "$1" "$2"; }

# ── tier A cases: each builds its own world, runs the script given as $1, and returns 0 if the behaviour holds ──
case_happy() {
  new_world happy; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; run_host happy
  host_is 0 "" "$(ANS 1 1 1 "$C1")" && [ "$(runuser_n)" = 1 ] && [ "$(wc -l < "$W/state/shm_dirs")" = 1 ]
}
case_noncanonical() { # must-PASS: 2 namespaces, a nested dotted branch, an annotated tag, lock dotfiles, an empty lost+found
  new_world noncanon; mkrepo "$REPO"
  : > "$W/store/repositories/.init.lock"; : > "$W/store/repositories/.ws-x9.init.lock"; mkdir "$W/store/repositories/lost+found"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  want_ref "$REPO" "$(nsref "$WT_B" "heads/$BR_B")" "$C2"
  want_ref "$REPO" "$(nsref "$WT_B" "tags/t1")" "$TAG_C"
  HS="$1"; run_host noncanon
  local two; two="$(printf '%s\n' "$C1" "$C2" | sort | paste -sd, -)"
  host_is 0 "" "$(ANS 2 3 2 "$two")"
}
case_cap() { # 4 heads, 3 distinct shas (two branches on one sha): heads=4, the two numerically smallest distinct shas
  new_world cap; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C3"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_B")" "$C3"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_C")" "$C1"
  want_ref "$REPO" "$(nsref "$WT_B" "heads/$BR_A")" "$C2"
  HS="$1"; run_host cap
  host_is 0 "" "$(ANS 2 4 4 "${SORTED3[0]},${SORTED3[1]}")"
}
# argv_ok — after a run in the current world: the recorded argv of the shimmed commands is exactly the modeled read-only form
argv_ok() {
  local st="$W/state" r=/mnt/git-data/repositories exp
  [ "$(cat "$st/mktemp_argv")" = "-d -p /dev/shm" ] || return 1
  [ "$(cat "$st/readlink_argv")" = "-f -- $r" ] || return 1
  exp="$(printf '%s\n' "-c %F -- $r" "-c %m -- $r" "-c %d:%i:%F -- $r" "-c %d:%i:%F:%U -- $r/$REPO" "-c %d:%i:%F -- $r" "-c %d:%i:%F:%U -- $r/$REPO")"
  [ "$(cat "$st/stat_argv")" = "$exp" ] || return 1
  [ "$(wc -l < "$st/find_argv")" = 3 ] || return 1
  if /usr/bin/grep -qE -- '(^| )-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)( |$)' "$st/find_argv"; then return 1; fi
  case "$(sed -n 1p "$st/find_argv")" in "-H $r -mindepth 1 -maxdepth 1 ! ( -type f ( -name .*.init.lock -o -name .init.lock ) ) ! ( -type d -name lost+found -empty ) -printf "*) : ;; *) return 1 ;; esac
  [ "$(sed -n 2p "$st/find_argv")" = "$r/$REPO -maxdepth 1 -name shallow -printf x" ] || return 1
  case "$(sed -n 3p "$st/find_argv")" in "-P $r/$REPO ( -path "*" -printf a -o -type l -printf s -o ( -path "*" -printf f ) -o -path "*" -prune") : ;; *) return 1 ;; esac
  return 0
}
case_happy_argv() { case_happy "$1" && argv_ok; }
mkmany() { # <n> — n heads refs on C1 in one namespace (git update-ref --stdin), into the current world's $REPO
  local i; for ((i = 0; i < $1; i++)); do printf 'create %s %s\n' "$(nsref "$WT_A" "heads/b$i.x_q")" "$C1"; done \
    | git --git-dir="$W/store/repositories/$REPO" update-ref --stdin || instrument "mkmany failed"
}
case_200() { new_world r200; mkrepo "$REPO"; mkmany 200; HS="$1"; run_host r200; host_is 0 "" "$(ANS 1 200 200 "$C1")"; }
case_201() { new_world r201; mkrepo "$REPO"; mkmany 201; HS="$1"; run_host r201; host_is 26 "$(ERRL 26 refs_unreadable)" ""; }
case_absent() {
  new_world absent; : > "$W/store/repositories/.init.lock"; mkdir "$W/store/repositories/lost+found"
  HS="$1"; run_host absent
  host_is 20 "$(ERRL 20 repos_absent)" "" && [ "$(runuser_n)" = 0 ]
}
case_two_repos() {
  new_world two; mkrepo "$REPO"; mkrepo "$REPO2"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; run_host two
  host_is 21 "refs-assert: rc=21 reason=repos_not_single repos=2" "" && [ "$(runuser_n)" = 0 ]
}
case_hostile_second() { # a hostile second directory name beside a clean first: refused, the name in no sink
  new_world hostile; mkrepo "$REPO"; mkrepo "$REPO_HOSTILE"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; run_host hostile
  host_is 21 "refs-assert: rc=21 reason=repos_not_single repos=2" "" && [ "$(runuser_n)" = 0 ] && ! grep -qF -- "$REPO_HOSTILE" "$HOUT" "$HERR"
}
case_symlink_entry() {
  new_world syment; mkrepo "$REPO"; ln -s "$REPO" "$W/store/repositories/$REPO_LINK"
  HS="$1"; run_host syment
  host_is 21 "refs-assert: rc=21 reason=repos_not_single repos=2" "" && [ "$(runuser_n)" = 0 ]
}
case_symlink_only() { # the only entry is a symlink to a real repository: it is not a real *.git directory
  new_world symonly; mkdir "$W/elsewhere"; cp -a "$TPL" "$W/elsewhere/$REPO"; ln -s "$W/elsewhere/$REPO" "$W/store/repositories/$REPO_LINK"
  HS="$1"; run_host symonly
  host_is 21 "refs-assert: rc=21 reason=repos_entry_not_repository" "" && [ "$(runuser_n)" = 0 ]
}
case_file_entry() {
  new_world fileent; : > "$W/store/repositories/$REPO_LINK"
  HS="$1"; run_host fileent
  host_is 21 "refs-assert: rc=21 reason=repos_entry_not_repository" "" && [ "$(runuser_n)" = 0 ]
}
case_nodotgit() {
  new_world nodotgit; mkrepo "$REPO_PLAIN"
  HS="$1"; run_host nodotgit
  host_is 21 "refs-assert: rc=21 reason=repos_entry_not_repository" "" && [ "$(runuser_n)" = 0 ]
}
case_lostfound_nonempty() {
  new_world lfne; mkdir "$W/store/repositories/lost+found"; : > "$W/store/repositories/lost+found/x"
  HS="$1"; run_host lfne
  host_is 21 "refs-assert: rc=21 reason=repos_entry_not_repository" "" && [ "$(runuser_n)" = 0 ]
}
case_repos_symlink() { # the repositories directory is itself a symlink to a real tree
  new_world reposlink; rm -rf "$W/store/repositories"; mkdir -p "$W/elsewhere"; cp -a "$TPL" "$W/elsewhere/$REPO"
  ln -s "$W/elsewhere" "$W/store/repositories"
  wref_elsewhere() { git --git-dir="$W/elsewhere/$REPO" update-ref "$1" "$2"; }
  wref_elsewhere "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; run_host reposlink
  host_is 21 "refs-assert: rc=21 reason=repositories_dir_not_plain" "" && [ "$(runuser_n)" = 0 ]
}
case_store_parent_link() { # the store root itself is a symlink: the directory is a real one, only the resolved path differs
  new_world parentlink; rm -rf "$W/store"; mkdir -p "$W/real-store/repositories"; ln -s "$W/real-store" "$W/store"
  cp -a "$TPL" "$W/real-store/repositories/$REPO"; git --git-dir="$W/real-store/repositories/$REPO" update-ref "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; run_host parentlink
  host_is 21 "refs-assert: rc=21 reason=repositories_dir_not_plain" "" && [ "$(runuser_n)" = 0 ]
}
case_not_on_mount() {
  new_world notmount; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/not_on_mount"
  HS="$1"; run_host notmount
  host_is 21 "refs-assert: rc=21 reason=repositories_dir_not_plain" "" && [ "$(runuser_n)" = 0 ]
}
case_never_pushed() { # a REAL never-pushed `git init --bare` (what git-data-provision.sh leaves)
  new_world never; mkbare "$REPO"
  HS="$1"; run_host never
  host_is 23 "$(ERRL 23 refs_none)" ""
}
case_outside_ns() { # refs exist, none under refs/soleur/worktrees/ (an unborn HEAD does not count either)
  new_world outns; mkrepo "$REPO"
  wref "$REPO" refs/heads/other "$C1"; wref "$REPO" refs/tags/t0 "$C1"; wref "$REPO" refs/soleur/other/heads/x "$C1"
  HS="$1"; run_host outns
  host_is 23 "$(ERRL 23 refs_none)" ""
}
case_tags_only() {
  new_world tagsonly; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "tags/t1")" "$TAG_C"; want_ref "$REPO" "$(nsref "$WT_B" "tags/t0")" "$C1"
  HS="$1"; run_host tagsonly
  host_is 24 "$(ERRL 24 refs_no_branch_tip)" ""
}
case_missing_object() { # one repository, well-formed names, one ref's object missing (git aborts): refs_unreadable
  new_world missobj; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/git_missing_object"
  HS="$1"; run_host missobj
  host_is 26 "$(ERRL 26 refs_unreadable)" ""
}
case_foreign_owner() { # a repository not owned by git: --git-dir skips git's own ownership check, so the SCRIPT refuses (stat %U)
  new_world foreign; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/owner_foreign"
  HS="$1"; run_host foreign
  host_is 27 "$(ERRL 27 repo_owner)" "" && [ "$(runuser_n)" = 0 ]
}
case_shallow() {
  new_world shallow; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; printf '%s\n' "$C1" > "$W/store/repositories/$REPO/shallow"
  HS="$1"; run_host shallow
  host_is 26 "$(ERRL 26 refs_unreadable)" "" && [ "$(runuser_n)" = 0 ]
}
case_broken_loose() { # a loose ref git silently skips with only a warning on stderr: rc 27 through the non-empty-stderr rule
  new_world brokenloose; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  mkdir -p "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_B/heads"
  printf '%040d\n' 0 | tr 0 x > "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_B/heads/$BR_C" # 41 bytes, not a sha: only git's warning shows it
  HS="$1"; run_host brokenloose
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_garbage_short() { # a loose ref file that is not 41 bytes (git would warn too, but the on-disk probe runs first): rc 27, a fixed word
  new_world garbshort; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  mkdir -p "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_B/heads"
  printf 'garbage\n' > "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_B/heads/$BR_C"
  HS="$1"; run_host garbshort
  host_is 27 "$(ERRL 27 ref_symref)" ""
}
case_dotdot_loose() {
  new_world dotdot; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  mkdir -p "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_A/heads"
  printf '%s\n' "$C2" > "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_A/heads/a..b"
  HS="$1"; run_host dotdot
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
# one ref per hostile class git ACCEPTS and the name regex rejects; each is the SECOND member beside a compliant first
# (Guard 1 mutation 2: a loop that stops after the first compliant ref would pass it).
HOSTILE_NAMES=('heads/a+b' 'heads/a,b' 'heads/x$y' 'heads/`tick`' 'heads/-dash' $'heads/caf\xc3\xa9' 'notes/x' 'heads/a#b' 'other/heads')
case_hostile_name() { # <script> <index>
  local nm="${HOSTILE_NAMES[$2]}"
  new_world "hn$2"; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  want_ref "$REPO" "$(nsref "$WT_B" "$nm")" "$C2"
  HS="$1"; run_host "hn$2"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_hostile_id() { # a worktree id outside the charset
  new_world hid; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  want_ref "$REPO" "refs/soleur/worktrees/zid+plus/heads/x" "$C2"
  HS="$1"; run_host hid
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_bad_sha_tree() { # a tree under heads/
  new_world badtree; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_B")" "$TREE2"
  HS="$1"; run_host badtree
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_bad_sha_tag_tree() { # a tag whose object is a tree
  new_world badtag; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "tags/t2")" "$TAG_T"
  HS="$1"; run_host badtag
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_bad_sha_head_tag() { # heads/ -> an ANNOTATED tag object (not a commit)
  new_world headtag; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_B")" "$TAG_C"
  HS="$1"; run_host headtag
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_bad_sha_lw_tag() { # <script> <tree|blob> — a LIGHTWEIGHT tags/ ref to a tree or a blob
  local o="$TREE2"; [ "$2" = blob ] && o="$BLOB"
  new_world "lwtag$2"; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "tags/lw")" "$o"
  HS="$1"; run_host "lwtag$2"
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_alternates() { # <script> <alternates|http-alternates|symlink> — objects that live outside the store
  new_world "alt$2"; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  mkdir -p "$W/store/repositories/$REPO/objects/info"
  case "$2" in
    alternates|http-alternates) printf '%s\n' "$W/elsewhere/objects" > "$W/store/repositories/$REPO/objects/info/$2" ;;
    symlink) ln -s "$W/elsewhere/alt" "$W/store/repositories/$REPO/objects/info/alternates" ;;
  esac
  HS="$1"; run_host "alt$2"
  host_is 27 "$(ERRL 27 repo_alternates)" "" && [ "$(runuser_n)" = 0 ]
}
case_symlink() { # <script> <variant> — a symlink the push could not have made
  new_world "sym$2"; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  local r="$W/store/repositories/$REPO"
  case "$2" in
    refs-soleur) mv "$r/refs/soleur" "$W/elsewhere-soleur"; ln -s "$W/elsewhere-soleur" "$r/refs/soleur" ;;
    deep-ref) mkdir -p "$r/refs/soleur/worktrees/$WT_B/heads"; ln -s "$r/refs/soleur/worktrees/$WT_A/heads/$BR_A" "$r/refs/soleur/worktrees/$WT_B/heads/lnk" ;;
    root-entry) ln -s "$W/elsewhere-hooks" "$r/hooks-link" ;;
    objects-entry) ln -s "$W/elsewhere-pack" "$r/objects/pack-link" ;;
    objects-file) mkdir -p "$r/objects/ab"; ln -s "$W/elsewhere-obj" "$r/objects/ab/cdef" ;;
    packed-refs) ln -s "$W/elsewhere-packed" "$r/packed-refs" ;;
  esac
  HS="$1"; run_host "sym$2"
  host_is 27 "$(ERRL 27 repo_symlink)" "" && [ "$(runuser_n)" = 0 ]
}
case_symref() { # <script> <live|dangling|dangling-alone|dangling-nested> — a symbolic ref under the namespace
  new_world "symref$2"; mkrepo "$REPO"
  local g="git --git-dir=$W/store/repositories/$REPO"
  case "$2" in
    live) wref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; $g symbolic-ref "$(nsref "$WT_A" "heads/ptr")" "$(nsref "$WT_A" "heads/$BR_A")" ;;
    dangling) wref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; $g symbolic-ref "$(nsref "$WT_A" "heads/ptr")" refs/heads/nonexistent ;;
    dangling-alone) $g symbolic-ref "$(nsref "$WT_A" "heads/ptr")" refs/heads/nonexistent ;;
    dangling-nested) wref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; $g symbolic-ref "$(nsref "$WT_B" "heads/deep/er/ptr")" refs/heads/nonexistent ;;
  esac
  HS="$1"; run_host "symref$2"
  host_is 27 "$(ERRL 27 ref_symref)" ""
}
case_lockfile_ok() { # a stray .lock file under the namespace (a push in flight) is not a ref: it neither refuses nor counts
  new_world lockfile; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  printf 'x\n' > "$W/store/repositories/$REPO/refs/soleur/worktrees/$WT_A/heads/${BR_B##*/}.lock"
  HS="$1"; run_host lockfile
  host_is 0 "" "$(ANS 1 1 1 "$C1")"
}
case_order_27_before_28() { # shape AND sha violated at once: 27 first
  new_world ord2728; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_B")" "$TREE2"; want_ref "$REPO" "$(nsref "$WT_A" 'heads/a+b')" "$C2"
  HS="$1"; run_host ord2728
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_order_28_before_24() { # sha violated and no branch tip: 28 first
  new_world ord2824; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "tags/t2")" "$TAG_T"
  HS="$1"; run_host ord2824
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_order_23_before_all() { # no ref under the namespace and a hostile ref outside it: 23
  new_world ord23; mkrepo "$REPO"; wref "$REPO" 'refs/heads/a+b' "$C1"
  HS="$1"; run_host ord23
  host_is 23 "$(ERRL 23 refs_none)" ""
}
# parser-level rows: a git stand-in answers a fixed output (the .lock and leading-dot branches real git refuses to create)
fake_run() { # <label> <git-rc> <stderr-text-or-""> <lines...> — a git stand-in answers a fixed output (git_fake_out is also the flag)
  local label="$1" grc="$2" gerr="$3"; shift 3
  new_world "fk$label"; mkrepo "$REPO"
  : > "$W/git_fake_out"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$W/git_fake_out"; done
  printf '%s' "$grc" > "$W/git_fake_rc"
  if [ -n "$gerr" ]; then printf '%s\n' "$gerr" > "$W/git_fake_err"; fi
  run_host "fk$label"
}
fl() { printf '%s\t%s\t%s\t<%s>\t<%s>' "$1" "$2" "$3" "${4:-}" "${5:-}"; } # a for-each-ref line: ref sha type [peel-type] [symref]
case_fake_lock() { # a branch ending in .lock: shape
  HS="$1"; fake_run lock 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "$(nsref "$WT_A" "heads/x.lock")" "$C2" commit)"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_dot() { # the id .. (a path component git refuses to create)
  HS="$1"; fake_run dot 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "refs/soleur/worktrees/../heads/x" "$C2" commit)"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_dot1() { # the id . (matches the id charset, so only the explicit equality refuses it)
  HS="$1"; fake_run dot1 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "refs/soleur/worktrees/./heads/x" "$C2" commit)"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_trailing_slash() {
  HS="$1"; fake_run slash 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "$(nsref "$WT_A" "heads/x/")" "$C2" commit)"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_bad_hex() { # a value that is not 40-hex (a sha256-length id)
  HS="$1"; fake_run hex 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "$(nsref "$WT_A" "heads/$BR_B")" "${C2}${C2:0:24}" commit)"
  host_is 28 "$(ERRL 28 refs_bad_sha)" ""
}
case_fake_stderr_rc0() { # git exits 0 but prints a warning (a broken ref skipped): rc 27 even though the output looks fine
  HS="$1"; fake_run warn 0 "warning: ignoring broken ref x" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_symref_field() { # a live symref reported by git (the fifth field): refused, and its target never lands in the peel-type field
  HS="$1"; fake_run fsym 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$(fl "$(nsref "$WT_A" "tags/p")" "$C2" commit "" "$(nsref "$WT_A" "heads/$BR_A")")"
  host_is 27 "$(ERRL 27 ref_symref)" ""
}
case_fake_collapsed() { # <script> <variant> — a line with the sentinel fields missing or empty (IFS collapses them): never a pass
  local bad
  case "$2" in
    four) bad="$(nsref "$WT_A" "tags/p")$(printf '\t%s\t%s\t%s' "$C2" commit "$(nsref "$WT_A" "heads/$BR_A")")" ;;
    empty) bad="$(nsref "$WT_A" "tags/p")$(printf '\t%s\t%s\t\t' "$C2" commit)" ;;
  esac
  HS="$1"; fake_run "fcol$2" 0 "" "$(fl "$(nsref "$WT_A" "heads/$BR_A")" "$C1" commit)" "$bad"
  host_is 27 "$(ERRL 27 refs_shape_failed)" ""
}
case_fake_selfcheck() { # an output the script cannot reconcile with itself (more lines than --count allows): unreadable
  local i lines=(); for ((i = 0; i < 202; i++)); do lines+=("$(fl "$(nsref "$WT_A" "heads/q$i")" "$C1" commit)"); done
  HS="$1"; fake_run over 0 "" "${lines[@]}"
  host_is 26 "$(ERRL 26 refs_unreadable)" ""
}
case_xtrace() {
  new_world xtrace; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; HOUT="$W/out"; HERR="$W/err"; HRC=0
  env -i PATH="$SH:/usr/bin:/bin" HOME="$W/home" WORLD="$W" REALGIT="$REALGIT" REFS_REPOS=/mnt/git-data/repositories bash -x -s < "$HS" > "$HOUT" 2> "$HERR" || HRC=$?
  assert_clean xtrace "$HOUT" "$HERR"
  [ "$HRC" = 16 ] && [ ! -s "$HOUT" ] && [ "$(runuser_n 2>/dev/null || echo 0)" = 0 ] && grep -qxF 'refs-assert: refusing to run under xtrace' "$HERR"
}
case_bad_input() { # <script> <REFS_REPOS value or UNSET>
  new_world "bi"; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"
  HS="$1"; HOUT="$W/out"; HERR="$W/err"; HRC=0; : > "$W/state/runuser_calls"
  if [ "$2" = UNSET ]; then
    env -i PATH="$SH:/usr/bin:/bin" HOME="$W/home" WORLD="$W" REALGIT="$REALGIT" bash -s < "$HS" > "$HOUT" 2> "$HERR" || HRC=$?
  else
    env -i PATH="$SH:/usr/bin:/bin" HOME="$W/home" WORLD="$W" REALGIT="$REALGIT" REFS_REPOS="$2" bash -s < "$HS" > "$HOUT" 2> "$HERR" || HRC=$?
  fi
  assert_clean bad-input "$HOUT" "$HERR"
  [ "$HRC" = 16 ] && [ ! -s "$HOUT" ] && [ "$(runuser_n)" = 0 ] && grep -q '^refs-assert: rc=16 reason=' "$HERR"
}
case_find_fail() { # the enumeration fails (no end record): an instrument fault, never "zero repositories"
  new_world findfail; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/find_fail"
  HS="$1"; run_host findfail
  host_is 16 "$(ERRL 16 enumeration_failed)" "" && [ "$(runuser_n)" = 0 ]
}
case_find_fail_empty() { # the enumeration fails on an EMPTY store: still an instrument fault (rc 16), never FAILED repos_absent (rc 20)
  new_world findfailempty; : > "$W/find_fail"
  HS="$1"; run_host findfailempty
  host_is 16 "$(ERRL 16 enumeration_failed)" "" && [ "$(runuser_n)" = 0 ]
}
case_find_fail_shallow() { # the shallow probe's find fails: an instrument fault, never "no shallow file"
  new_world findshallow; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/find_fail_shallow"
  HS="$1"; run_host findshallow
  host_is 16 "$(ERRL 16 shallow_probe)" "" && [ "$(runuser_n)" = 0 ]
}
case_find_fail_shape() { # the alternates/symlink probe's find fails: an instrument fault, never "nothing found"
  new_world findshape; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/find_fail_shape"
  HS="$1"; run_host findshape
  host_is 16 "$(ERRL 16 shape_probe)" "" && [ "$(runuser_n)" = 0 ]
}
case_stat_fail() { # <script> <k> — the k-th stat call fails: rc 16 stat_failed at every site
  new_world "statfail$2"; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; printf '%s' "$2" > "$W/stat_fail_at"
  HS="$1"; run_host "statfail$2"
  host_is 16 "$(ERRL 16 stat_failed)" ""
}
case_toctou() { # the repository is replaced between the identity record and the re-check
  new_world toctou; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/toctou_swap"
  HS="$1"; run_host toctou
  host_is 16 "$(ERRL 16 identity_changed)" ""
}
case_toctou_repos() { # the repositories DIRECTORY is replaced between the identity record and the re-check
  new_world toctourepos; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/toctou_swap_repos"
  HS="$1"; run_host toctourepos
  host_is 16 "$(ERRL 16 identity_changed)" ""
}
case_term() { # a TERM delivered mid-run: the trap turns it into rc 16 (a default TERM would be 143) and the scratch directory is removed
  new_world term; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/term_self"
  HS="$1"; run_host term
  host_is 16 "" "" && [ -s "$W/state/shm_dirs" ]
}
case_noisy() { # every shimmed command also prints a fixture name to stderr (and rm/rmdir to stdout): none of it may surface
  new_world noisy; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; printf '%s' "$REPO_HOSTILE" > "$W/noisy"
  HS="$1"; run_host noisy
  host_is 0 "" "$(ANS 1 1 1 "$C1")" && ! grep -qF -- "$REPO_HOSTILE" "$HOUT" "$HERR"
}
case_owner_flip() { # the repository's owner changes between the identity record and the re-check
  new_world ownerflip; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/owner_flip"
  HS="$1"; run_host ownerflip
  host_is 16 "$(ERRL 16 identity_changed)" ""
}
case_all() { # <case-fn> <script> <variant...> — every variant of a parameterised case must hold
  local f="$1" sc="$2" v; shift 2
  for v in "$@"; do "$f" "$sc" "$v" || return 1; done
}
case_sort_trunc() { # the sort returns one line fewer than there are distinct shas: the self-check refuses, never a short line
  new_world sorttrunc; mkrepo "$REPO"
  want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_B")" "$C2"; : > "$W/sort_trunc"
  HS="$1"; run_host sorttrunc
  host_is 26 "$(ERRL 26 refs_unreadable)" ""
}
case_stdin() { # the git stand-in reads stdin; the script is delivered through a PIPE with a long unread tail after its last line
  new_world stdin; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; : > "$W/runuser_stdin"
  local body="$W/body-with-tail"; { cat "$1"; local i; for ((i = 0; i < 400; i++)); do printf '# tail line %s: unread script text the git child must never see\n' "$i"; done; } > "$body"
  HS="$body"; run_host stdin
  [ "$HRC" = 0 ] && [ "$(cat "$HOUT")" = "$(ANS 1 1 1 "$C1")" ] && [ -f "$W/state/runuser_stdin_bytes" ] && [ ! -s "$W/state/runuser_stdin_bytes" ]
}
case_no_refs_fixture() { # Guard 1 harness (a): the builder creates no refs -> the happy row must go RED
  FIXTURE_NO_REFS=1; local r=0; case_happy "$SCRIPT" || r=$?; FIXTURE_NO_REFS=0; return "$r"
}

# ── mutation harness ─────────────────────────────────────────────────────────────────────
MUTANTS_RUN=0
mkdir -p "$T/mut"
# mutate <name> <src> <sed -E expression>: copies, applies, and requires the edit to LAND (the file differs)
MUT=""
mutate() {
  MUT="$T/mut/$1"; cp "$2" "$MUT"; sed -E -i "$3" "$MUT"
  if cmp -s "$2" "$MUT"; then no "mutation $1: the sed expression did not change the file (the row would prove nothing)"; return 1; fi
  if ! bash -n "$MUT" 2>/dev/null; then no "mutation $1: the mutant does not parse (a RED row would prove only the syntax error)"; return 1; fi
  return 0
}
# mutate_cutover <name> <sed -E expression>: a mutated COPY of the verb, in its own directory beside a copy of the host script
mutate_cutover() {
  local d="$T/mutc/$1"; mkdir -p "$d"; cp "$CUTOVER" "$d/git-data-cutover.sh"; cp "$SCRIPT" "$d/git-data-refs-assert.sh"
  sed -E -i "$2" "$d/git-data-cutover.sh"; MUT="$d/git-data-cutover.sh"
  if cmp -s "$CUTOVER" "$MUT"; then no "mutation $1: the sed expression did not change the verb (the row would prove nothing)"; return 1; fi
  return 0
}
# mutant_red <name> <case-function> <args...> — the case, run on the mutated script, must FAIL
mutant_red() {
  local name="$1"; shift
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  if "$@"; then no "mutant $name: the case stayed GREEN on the mutated script"; else ok "mutant $name: goes RED (the edit landed and the case caught it)"; fi
}

# ══════════════════════════════════════════════════════════════════════════════════════════
echo "--- tier A: the host script"
[ -f "$SCRIPT" ] && ok "A00 the host script exists" || no "A00 the host script $SCRIPT does not exist"
if [ ! -f "$SCRIPT" ]; then
  echo "=== git-data-refs-assert.test.sh: ${pass} passed, ${fail} failed (host script missing) ==="; exit 1
fi

if case_happy "$SCRIPT"; then ok "A01 one repository, one branch tip: rc 0 and EXACTLY the one anchored answer line, empty stderr"; else no "A01 happy path: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if argv_ok; then ok "A01b the shims logged EXACTLY the modeled read-only argv: mktemp -d -p /dev/shm, readlink -f --, the six stat forms (owner folded into the repository's two identity stats), three finds none of which can delete, exec or write (-delete -exec -ok -fprint*)"; else no "A01b recorded argv drifted: mktemp=[$(cat "$W/state/mktemp_argv")] readlink=[$(cat "$W/state/readlink_argv")] stat=[$(tr '\n' '|' < "$W/state/stat_argv")] find=[$(tr '\n' '|' < "$W/state/find_argv" | cut -c1-500)]"; fi
if case_noncanonical "$SCRIPT"; then ok "A02 (must-PASS non-canonical) two namespaces, a nested dotted branch, an annotated tag, lock dotfiles and an empty lost+found: namespaces=2 refs=3 heads=2, only the heads shas"; else no "A02 non-canonical: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_cap "$SCRIPT"; then ok "A03 four heads over three distinct shas: heads=4 and the cap of 2 numerically smallest DISTINCT shas, sorted by sha value"; else no "A03 cap/sort/dedupe: rc=$HRC out=[$(cat "$HOUT")]"; fi
if case_200 "$SCRIPT"; then ok "A04 (must-PASS) exactly 200 refs pass: the bound is on the 201st line"; else no "A04 200 refs: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_201 "$SCRIPT"; then ok "A05 201 refs: rc 26 refs_unreadable (the bound), nothing printed"; else no "A05 201 refs: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_no_refs_fixture; then no "A06 harness (a): a fixture builder that creates no refs still passed the happy row"; else ok "A06 harness (a): break the SUITE (the builder creates no refs) and the happy-path row goes RED"; fi

echo "--- tier A: refusals, one per row of the exit-code table (whole stdout and stderr)"
if case_absent "$SCRIPT"; then ok "A10 rc 20 repos_absent: only lock dotfiles and an empty lost+found, and no ref was read"; else no "A10 absent: rc=$HRC err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
if case_two_repos "$SCRIPT"; then ok "A11 rc 21 two repositories: stderr is a fixed word and digits only, and NO ref was read"; else no "A11 two repos: rc=$HRC err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
if case_hostile_second "$SCRIPT"; then ok "A12 rc 21 a hostile second directory name (::error::) beside a clean first: refused, the name in no sink"; else no "A12 hostile second: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_symlink_entry "$SCRIPT"; then ok "A13 rc 21 a symlink entry beside a repository"; else no "A13 symlink entry: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_symlink_only "$SCRIPT"; then ok "A14 rc 21 a lone symlink to a real repository is not a real *.git directory"; else no "A14 lone symlink: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_file_entry "$SCRIPT"; then ok "A15 rc 21 a plain-file entry named *.git"; else no "A15 file entry: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_nodotgit "$SCRIPT"; then ok "A16 rc 21 a directory not named *.git"; else no "A16 non-.git dir: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_lostfound_nonempty "$SCRIPT"; then ok "A17 rc 21 a NON-empty lost+found is an entry, not an exclusion"; else no "A17 lost+found: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_repos_symlink "$SCRIPT"; then ok "A18 rc 21 a symlinked repositories directory (Guard 1 mutation 7's fixture)"; else no "A18 symlinked repositories dir: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_store_parent_link "$SCRIPT"; then ok "A18b rc 21 the store root is a symlink: the directory is real, only its resolved path differs (readlink identity)"; else no "A18b symlinked store root: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_not_on_mount "$SCRIPT"; then ok "A19 rc 21 the repositories directory is not on the store mount"; else no "A19 not on mount: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_never_pushed "$SCRIPT"; then ok "A20 rc 23 refs_none on a REAL never-pushed git init --bare (provisioning seeds nothing)"; else no "A20 never pushed: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_outside_ns "$SCRIPT"; then ok "A21 rc 23 refs outside refs/soleur/worktrees/ do not count (heads, tags and a sibling namespace)"; else no "A21 outside namespace: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_tags_only "$SCRIPT"; then ok "A22 rc 24 refs_no_branch_tip: tags-only never passes"; else no "A22 tags-only: rc=$HRC out=[$(cat "$HOUT")]"; fi
if case_missing_object "$SCRIPT"; then ok "A23 rc 26 a missing object (git aborts), one repository, well-formed names"; else no "A23 missing object: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_foreign_owner "$SCRIPT"; then ok "A24 rc 27 repo_owner: a repository not owned by git is refused by the script's own owner check (--git-dir skips git's check), and no ref was read"; else no "A24 foreign owner: rc=$HRC err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
if case_shallow "$SCRIPT"; then ok "A25 rc 26 a repository with a shallow file, and no git verb was run"; else no "A25 shallow: rc=$HRC err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
if case_broken_loose "$SCRIPT"; then ok "A26 rc 27 a garbage loose ref git skips with only a warning (the non-empty-stderr rule)"; else no "A26 garbage loose ref: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_garbage_short "$SCRIPT"; then ok "A26b rc 27 ref_symref: a loose ref file that is not exactly 41 bytes (a symref, dangling or not, or a truncated file) is refused by the on-disk probe"; else no "A26b short garbage loose ref: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_dotdot_loose "$SCRIPT"; then ok "A27 rc 27 a heads/a..b loose file written by hand (git cannot create it)"; else no "A27 a..b: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
for _i in "${!HOSTILE_NAMES[@]}"; do
  if case_hostile_name "$SCRIPT" "$_i"; then ok "A28.$_i rc 27 a hostile name git accepts, as the SECOND member beside a compliant ref (class $_i)"; else no "A28.$_i hostile name $_i: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
done
if case_hostile_id "$SCRIPT"; then ok "A29 rc 27 a worktree id outside the charset"; else no "A29 hostile id: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_bad_sha_tree "$SCRIPT"; then ok "A30 rc 28 a tree under heads/"; else no "A30 tree under heads: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_bad_sha_tag_tree "$SCRIPT"; then ok "A31 rc 28 a tag to a tree"; else no "A31 tag to tree: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_bad_sha_head_tag "$SCRIPT"; then ok "A31b rc 28 a heads/ ref to an ANNOTATED tag object (a tag is not a branch tip)"; else no "A31b heads to annotated tag: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
for _o in tree blob; do
  if case_bad_sha_lw_tag "$SCRIPT" "$_o"; then ok "A31c.$_o rc 28 a lightweight tags/ ref to a $_o"; else no "A31c.$_o lightweight tag to $_o: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
done
for _v in alternates http-alternates symlink; do
  if case_alternates "$SCRIPT" "$_v"; then ok "A50.$_v rc 27 repo_alternates: objects/info/$_v makes the repository not self-contained, and no ref was read"; else no "A50.$_v alternates ($_v): rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
done
for _v in refs-soleur deep-ref root-entry objects-entry objects-file packed-refs; do
  if case_symlink "$SCRIPT" "$_v"; then ok "A51.$_v rc 27 repo_symlink: a symlink ($_v) a push cannot have made, and no ref was read"; else no "A51.$_v symlink ($_v): rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
done
for _v in live dangling dangling-alone dangling-nested; do
  if case_symref "$SCRIPT" "$_v"; then ok "A52.$_v rc 27 ref_symref: a symbolic ref ($_v) under the namespace is refused (git skips a dangling one silently, so it is probed on disk)"; else no "A52.$_v symref ($_v): rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
done
if case_lockfile_ok "$SCRIPT"; then ok "A52b (must-PASS) a stray .lock file under the namespace is not a ref: no refusal, not counted"; else no "A52b lock file: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_order_27_before_28 "$SCRIPT"; then ok "A32 order: shape (27) is reported before sha type (28)"; else no "A32 order 27/28: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_order_28_before_24 "$SCRIPT"; then ok "A33 order: sha type (28) is reported before no-branch-tip (24)"; else no "A33 order 28/24: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_order_23_before_all "$SCRIPT"; then ok "A34 order: no ref in the namespace (23) wins over a hostile ref outside it"; else no "A34 order 23: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_fake_lock "$SCRIPT"; then ok "A35 (parser-level, git stand-in) a .lock branch -> rc 27"; else no "A35 .lock: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_fake_dot "$SCRIPT"; then ok "A36 (parser-level) the id .. -> rc 27"; else no "A36 id ..: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_fake_dot1 "$SCRIPT"; then ok "A36b (parser-level) the id . -> rc 27 (the charset admits it; only the equality refuses it)"; else no "A36b id .: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_fake_symref_field "$SCRIPT"; then ok "A36c (parser-level) a symref reported in the fifth field -> rc 27 ref_symref (its target never reaches the peel-type field)"; else no "A36c symref field: rc=$HRC err=[$(cat "$HERR")]"; fi
for _v in four empty; do
  if case_fake_collapsed "$SCRIPT" "$_v"; then ok "A36d.$_v (parser-level) a line with the optional fields missing or empty ($_v) is off-shape -> rc 27, never a pass (tab is IFS whitespace)"; else no "A36d.$_v collapsed fields: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
done
if case_fake_trailing_slash "$SCRIPT"; then ok "A37 (parser-level) a trailing slash -> rc 27"; else no "A37 trailing slash: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_fake_bad_hex "$SCRIPT"; then ok "A38 (parser-level) a value that is not 40-hex -> rc 28"; else no "A38 bad hex: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_fake_stderr_rc0 "$SCRIPT"; then ok "A39 (parser-level) git exits 0 with a warning on stderr -> rc 27, never a pass"; else no "A39 stderr rc0: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_fake_selfcheck "$SCRIPT"; then ok "A40 (parser-level) more lines than the bound -> rc 26"; else no "A40 over-bound: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_xtrace "$SCRIPT"; then ok "A41 rc 16 under xtrace, before anything is read"; else no "A41 xtrace: rc=$HRC err=[$(cat "$HERR")]"; fi
for _v in UNSET "" "relative/path" "/mnt/git-data/../etc" "/mnt/git-data/repositories;id" "/etc/repositories"; do
  if case_bad_input "$SCRIPT" "$_v"; then ok "A42 rc 16 an invalid REFS_REPOS [$_v]: nothing read"; else no "A42 bad input [$_v]: rc=$HRC err=[$(cat "$HERR")] calls=$(runuser_n)"; fi
done
if case_find_fail "$SCRIPT"; then ok "A43 rc 16 enumeration_failed: an enumeration that fails is an instrument fault, never zero repositories"; else no "A43 find fails: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_find_fail_empty "$SCRIPT"; then ok "A43b rc 16 enumeration_failed on an EMPTY store: a failing find is INCONCLUSIVE, never the FAILED rc 20 repos_absent"; else no "A43b find fails on an empty store: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_find_fail_shallow "$SCRIPT"; then ok "A43c rc 16 shallow_probe: a failing shallow probe is an instrument fault, never 'no shallow file'"; else no "A43c shallow probe fails: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_find_fail_shape "$SCRIPT"; then ok "A43d rc 16 shape_probe: a failing alternates/symlink probe is an instrument fault, never 'nothing found'"; else no "A43d shape probe fails: rc=$HRC err=[$(cat "$HERR")]"; fi
for _k in 1 2 3 4 5 6; do
  if case_stat_fail "$SCRIPT" "$_k"; then ok "A43e.$_k rc 16 stat_failed when the stat call number $_k of the run fails (every stat site fails closed)"; else no "A43e.$_k stat call $_k fails: rc=$HRC err=[$(cat "$HERR")]"; fi
done
if case_toctou "$SCRIPT"; then ok "A44 rc 16 identity_changed: the repository replaced between the identity record and the re-check"; else no "A44 toctou: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_toctou_repos "$SCRIPT"; then ok "A44b rc 16 identity_changed: the repositories DIRECTORY replaced between the identity record and the re-check"; else no "A44b toctou (repositories dir): rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_term "$SCRIPT"; then ok "A44c a TERM mid-run exits rc 16 (the trap) with nothing printed, and the scratch directory is removed"; else no "A44c TERM: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_noisy "$SCRIPT"; then ok "A44d every shimmed command also prints a fixture name to stderr (rm/rmdir to stdout too): none of it reaches stdout or stderr"; else no "A44d noisy commands: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_owner_flip "$SCRIPT"; then ok "A44f rc 16 identity_changed: the owner changing between the record and the re-check is caught (the owner is part of the identity string)"; else no "A44f owner flip: rc=$HRC err=[$(cat "$HERR")]"; fi
if case_sort_trunc "$SCRIPT"; then ok "A44e rc 26 a sort that returns fewer lines than there are distinct shas is refused by the self-check, never a short shas= field"; else no "A44e truncated sort: rc=$HRC out=[$(cat "$HOUT")] err=[$(cat "$HERR")]"; fi
if case_stdin "$SCRIPT"; then ok "A45 stdin delivery: a git stand-in that reads stdin reads ZERO bytes of the script's unread tail"; else no "A45 stdin: rc=$HRC bytes=[$(cat "$W/state/runuser_stdin_bytes" 2>/dev/null)]"; fi

# the scanner must itself be able to fail
_sf="$T/scan-probe.txt"; printf 'leak %s\n' "$WT_A" > "$_sf"; _r=0; scan_files "$_sf" || _r=$?
if [ "$_r" = 1 ]; then ok "A46 harness: the print scanner flags a fixture identifier"; else no "A46 the scanner did not flag a planted identifier (rc=$_r)"; fi
printf 'sha %s\n' "$C1" > "$_sf"; _r=0; scan_files "$_sf" || _r=$?
if [ "$_r" = 1 ]; then ok "A47 harness: the print scanner flags a stray 40-hex string outside the answer line"; else no "A47 the scanner missed a stray sha (rc=$_r)"; fi
_save=("${SCAN_IDS[@]}"); SCAN_IDS=(); _r=0; scan_files "$_sf" || _r=$?; SCAN_IDS=("${_save[@]}")
if [ "$_r" = 2 ]; then ok "A48 harness: with the identifier list emptied the scan row goes RED (instrument failure, never a clean pass)"; else no "A48 an emptied identifier list passed the scan (rc=$_r)"; fi
printf '%s\n' "$(ANS 1 1 1 "$C1")" > "$_sf"; _r=0; scan_files "$_sf" || _r=$?
if [ "$_r" = 0 ]; then ok "A49 harness: the matched answer line (its shas= field) is the one place a 40-hex string is allowed"; else no "A49 the scanner rejected the answer line (rc=$_r)"; fi

echo "--- tier A: parity and static rows"
par_py() { python3 - "$@" <<'PY'
import re, sys
script = open(sys.argv[1]).read()
cut = open(sys.argv[2]).read()
boot = open(sys.argv[3]).read()
tf = open(sys.argv[4]).read()
hdr = script.split("# EXIT CODES", 1)[1].split("\n# Inputs", 1)[0]
rows = re.findall(r"^#\s+([0-9]+)\s+([a-z_]+)\s+(REFS-CONFIRMED|FAILED|INCONCLUSIVE)\b", hdr, re.M)
tbl = {int(a): (b, c) for a, b, c in rows}
code = "\n".join(l for l in script.splitlines() if not l.lstrip().startswith("#"))
die_codes = set(int(m) for m in re.findall(r"\bdie ([0-9]+) ", code))
fn = cut.split("mode_refs_assert() {", 1)[1].split("\n}\n", 1)[0]
arms = {int(a): w for a, w in re.findall(r"^\s+([0-9]+)\) _refs_refuse ([a-z_]+)", fn, re.M)}
cls = re.search(r"_refs_class\(\) \{(.*?)\n\}", cut, re.S)
failed = set(re.findall(r"[a-z_]+", re.search(r"([a-z_|]+)\) (?:printf|echo) FAILED", cls.group(1)).group(1))) if cls else set()
print("TABLE", sorted(tbl))
print("DIE", sorted(die_codes))
print("ARMS", sorted(arms))
print("TABLE_EQ_DIE", set(tbl) - {0} == die_codes)
arms.pop(96, None)
print("ARMS_EQ_TABLE", {k: v[0] for k, v in tbl.items() if k not in (0, 16)} == arms)
print("CLASSES", bool(arms) and all((tbl[k][1] == "FAILED") == (arms[k] in failed) for k in arms))
print("FAILED_SET", sorted(failed))
fl = [l for l in code.splitlines() if "find -H" in l and "-mindepth 1" in l]
sx = sorted(re.findall(r"-name '?([^ ')]+)'?", fl[0])) if len(fl) == 1 else []
bx = sorted(re.findall(r"! -name '?([^ ']+)'?", re.search(r"_repo_count\(\) \{.*?\n\}", boot, re.S).group(0)))
typed = bool(fl) and bool(re.search(r"-type f \\\( -name '\.\*\.init\.lock' -o -name '\.init\.lock' \\\)", fl[0])) and bool(re.search(r"-type d -name lost\+found -empty", fl[0]))
print("EXCL", sx, bx, sx == bx and len(sx) == 3, "TYPED", typed)
print("ROSTER_FILE", "git-data-refs-assert" in tf)
PY
}
par_py "$SCRIPT" "$CUTOVER" "$DIR/git-data-bootstrap.sh" "$USERDATA_TF" > "$T/parity.out" 2> "$T/parity.err"
if [ -s "$T/parity.err" ]; then no "PAR python: $(head -c 300 "$T/parity.err")"; fi
par() { grep -qxF "$1" "$T/parity.out"; }
if par "TABLE_EQ_DIE True"; then ok "PAR1 the header exit-code table equals the die calls (set identity)"; else no "PAR1 table vs die calls: $(grep -E '^(TABLE|DIE) ' "$T/parity.out" | tr '\n' ' ')"; fi
if par "ARMS_EQ_TABLE True"; then ok "PAR2 the verb's case arms equal the table (code -> word, set identity; 0 and 16 are the pass and probe_failed)"; else no "PAR2 arms vs table: $(grep -E '^(TABLE|ARMS) ' "$T/parity.out" | tr '\n' ' ')"; fi
if par "CLASSES True"; then ok "PAR3 the verb's FAILED set equals the table's class column"; else no "PAR3 class column: $(grep -E '^(CLASSES|FAILED_SET)' "$T/parity.out" | tr '\n' ' ')"; fi
if grep -q '^EXCL .* True TYPED True$' "$T/parity.out"; then ok "PAR4 the script's exclusion predicate names exactly the bootstrap's _repo_count exclusions (.*.init.lock, .init.lock, lost+found) AND keeps the -type tokens that narrow them (lock files: -type f; lost+found: -type d -empty)"; else no "PAR4 exclusion predicate: $(grep '^EXCL' "$T/parity.out")"; fi
if par "ROSTER_FILE False"; then ok "PAR5 git-data-refs-assert is named by no file() binding of modules/git-data-userdata/main.tf (stdin-delivered, not hash-bound)"; else no "PAR5 the host script appears in the userdata module"; fi
_n="$(grep -o 'file("${path.module}/../../[^"]*")' "$USERDATA_TF" | wc -l)"
# 16 is the plan's AC1 constant (the rung-2 evidence hash binds exactly these payloads); a different count means the roster
# changed under this PR, and AC1 and the hash-bound intersection must be re-run before the number is restated here.
_missing=""; while IFS= read -r _f; do [ -f "$DIR/modules/git-data-userdata/$_f" ] || _missing="$_missing $_f"; done < <(grep -o 'file("${path.module}/../../[^"]*")' "$USERDATA_TF" | sed -E 's#^file\("\$\{path.module\}/##; s#"\)$##')
if [ "$_n" = 16 ] && [ -z "$_missing" ]; then ok "PAR6 the hash roster is 16 file() bindings (the plan's AC1 constant), and every bound payload exists"; else no "PAR6 the roster size is $_n (the plan counted 16) or a bound payload is missing:$_missing"; fi
if [ -z "$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -E '\b(STORE_DEVICE|STORE_VERIFIED|cutover_freeze|MOUNT_ROOT|GIT_DATA_ROOT|REPO_ROOT)=')" ]; then ok "PAR7 the script assigns none of STORE_DEVICE, STORE_VERIFIED, cutover_freeze, MOUNT_ROOT, GIT_DATA_ROOT, REPO_ROOT (the P3 definer population is unchanged)"; else no "PAR7 the script assigns a P3 definer variable"; fi
# the format string pin, literal
if grep -qF -- "--format='%(refname)%09%(objectname)%09%(objecttype)%09<%(*objecttype)>%09<%(symref)>'" "$SCRIPT" && grep -qF -- '--count=$((RA_BOUND + 1))' "$SCRIPT" && grep -qxF '  readonly RA_BOUND=200' "$SCRIPT"; then ok "PAR8 the for-each-ref format (both optional fields in a non-whitespace sentinel) and the bound (RA_BOUND=200, count RA_BOUND+1 = 201 in the modeled argv) are pinned literally in the script"; else no "PAR8 the format/bound literal is absent"; fi
# the write-verb anchors. The dispatcher's verb list is DERIVED from the dispatcher (SHIM_VERBS); every one is a symlink
# in the shim directory (an arm that is never linked is a dead guard), the mutation list is a subset of it, and the
# git verbs are refused by the runuser shim's exact-argv rule.
_unlinked=""; for _v in $SHIM_VERBS; do [ -L "$SH/$_v" ] || _unlinked="$_unlinked $_v"; done
_notin=""; for _v in $WRITE_VERBS_PATH; do case " $SHIM_VERBS " in *" $_v "*) : ;; *) _notin="$_notin $_v" ;; esac; done
if [ -n "$SHIM_VERBS" ] && [ -z "$_unlinked" ] && [ -z "$_notin" ] && [ "$(printf '%s\n' $SHIM_VERBS | wc -l)" -ge 20 ] && [ "$WRITE_VERBS_GIT" = "gc update-ref" ]; then ok "PAR9 anchor: every verb the shim dispatcher names ($(printf '%s' "$SHIM_VERBS" | wc -w) of them, derived from the dispatcher) is symlinked into the shim directory; the mutation list is a subset; gc and update-ref are refused by the runuser shim's exact-argv rule"; else no "PAR9 shim verbs drifted: unlinked=[$_unlinked] mutation-list-not-in-dispatcher=[$_notin] verbs=[$SHIM_VERBS]"; fi

# ── static censuses of the script itself: the closed command set, the closed redirect set, the exit paths ──────────
cat > "$T/census.py" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
raws = []       # raw text of every quoted piece, by placeholder index
segs = []       # code segments (quoted pieces and nested substitutions replaced by placeholders)

def ph(raw):
    raws.append(raw)
    return "\x01%d\x02" % (len(raws) - 1)

def skip_braces(i):                       # s[i:] starts at "${": return the index after the matching "}"
    d = 0
    while i < len(s):
        c = s[i]
        if c == "\\": i += 2; continue
        if c == "'":
            i = s.index("'", i + 1) + 1; continue
        if c == '"':
            i = dq(i + 1)[0]; continue
        if s.startswith("${", i): d += 1; i += 2; continue
        if c == "}":
            d -= 1; i += 1
            if d == 0: return i
            continue
        i += 1
    return i

def dq(i):                                # inside double quotes; returns (index after the closing quote, raw)
    start = i
    while i < len(s):
        c = s[i]
        if c == "\\": i += 2; continue
        if c == '"': return i + 1, s[start - 1:i + 1]
        if s.startswith("$(", i) and not s.startswith("$((", i):
            i, inner = code(i + 2, True); segs.append(inner); continue
        if s.startswith("${", i): i = skip_braces(i); continue
        i += 1
    return i, s[start - 1:]

def code(i, sub):
    out = []
    while i < len(s):
        c = s[i]
        if c == "#" and (not out or out[-1] in " \t\n;(&|"):
            while i < len(s) and s[i] != "\n": i += 1
            continue
        if c == "'":
            j = s.index("'", i + 1); out.append(ph(s[i:j + 1])); i = j + 1; continue
        if c == '"':
            j, raw = dq(i + 1); out.append(ph(raw)); i = j; continue
        if c == "$" and s.startswith("$'", i):
            j = i + 2
            while s[j] != "'" or s[j - 1] == "\\": j += 1
            out.append(ph(s[i:j + 1])); i = j + 1; continue
        if c == "\\":
            out.append(ph(s[i:i + 2])); i += 2; continue
        if s.startswith("$((", i):
            d = 0; j = i
            while j < len(s):
                if s.startswith("((", j): d += 1; j += 2; continue
                if s.startswith("))", j):
                    d -= 1; j += 2
                    if d == 0: break
                    continue
                j += 1
            out.append(ph(s[i:j])); i = j; continue
        if s.startswith("$(", i) or s.startswith("<(", i) or s.startswith(">(", i):
            j, inner = code(i + 2, True); segs.append(inner); out.append(ph("SUBST")); i = j; continue
        if s.startswith("${", i):
            j = skip_braces(i); out.append(ph(s[i:j])); i = j; continue
        if c == ")" and sub:
            return i + 1, "".join(out)
        out.append(c); i += 1
    return i, "".join(out)

_, top = code(0, False)
segs.insert(0, top)

def unph(t):
    return re.sub(r"\x01(\d+)\x02", lambda m: raws[int(m.group(1))], t)

KEYWORDS = {"if", "then", "else", "elif", "fi", "while", "until", "do", "done", "for", "in", "esac", "!", "time", "select"}
cmds, reds, exits, returns = [], [], [], []
for seg in segs:
    seg = re.sub(r"\[\[.*?\]\]", " T ", seg, flags=re.S)                    # conditional expressions
    seg = re.sub(r"\b\w+\(\)\s*\{", "{", seg)                                # function headers
    seg = re.sub(r"=\([^)]*\)", "=A", seg)                                   # array literals
    # redirections: every write form is collected, then removed
    def red(m):
        reds.append("%s%s%s" % (m.group(1), m.group(2), unph(m.group(3))))
        return " "
    seg = re.sub(r"(\d*)(>>|>&|&>|>)\s*(-|\d+|\x01\d+\x02|[^\s;|&()\x01]*)", red, seg)
    seg = re.sub(r"(\d*)(<<<|<)\s*(\x01\d+\x02|[^\s;|&()\x01]*)", " ", seg)
    seg = re.sub(r"(?m)(^|;;|\bin\b)\s*[^\s;()]+(\s*\|\s*[^\s;()]+)*\s*\)", r"\1 ", seg)  # case labels
    for st in re.split(r";;|;|&&|\|\||\||\n|\{|\}|&", seg):
        w = st.split()
        while w and (w[0] in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\[.*\])?=", w[0])):
            w = w[1:]
        if not w or w[0] == "T": continue
        if w[0] == "case": continue
        cmd = unph(w[0])
        cmds.append(cmd)
        if cmd == "exit": exits.append(unph(" ".join(w)))
        if cmd == "return": returns.append(unph(" ".join(w)))
print("CMDS", " ".join(sorted(set(cmds))))
print("REDIRS", "\t".join(sorted(reds)))
print("EXITS", "\t".join(sorted(exits)))
print("RETURNS", "\t".join(returns))
print("FD4", sum(1 for r in reds if r == ">&4"))
PY
census() { python3 "$T/census.py" "$1"; }
CMD_ALLOWED=": [ break cd continue die exec exit export find local mapfile mktemp printf ra_main read readlink readonly return rm rmdir runuser say set shift sort stat trap"
RED_ALLOWED=$'1>/dev/null\t2>/dev/null\t2>"$sd/err"\t3>&-\t3>&2\t4>&-\t4>&1\t>&2\t>&3\t>&4'
# census_ok <script> — the closed command set, the closed redirect set, ONE >&4 write, ONE return 0, exits only in the known forms
census_ok() {
  local out cmds reds exits rets fd4 c r e bad=0 nexit tb=$'\t'
  out="$(census "$1")" || return 2
  cmds="$(sed -n 's/^CMDS //p' <<< "$out")"; reds="$(sed -n 's/^REDIRS //p' <<< "$out")"; exits="$(sed -n 's/^EXITS //p' <<< "$out")"
  rets="$(sed -n 's/^RETURNS //p' <<< "$out")"; fd4="$(sed -n 's/^FD4 //p' <<< "$out")"
  [ -n "$cmds" ] && [ -n "$reds" ] || return 2
  for c in $cmds; do case " $CMD_ALLOWED " in *" $c "*) : ;; *) CENSUS_WHY="command [$c]"; bad=1 ;; esac; done
  while IFS= read -r r; do [ -n "$r" ] || continue; case "$tb$RED_ALLOWED$tb" in *"$tb$r$tb"*) : ;; *) CENSUS_WHY="redirect [$r]"; bad=1 ;; esac; done < <(tr '\t' '\n' <<< "$reds")
  nexit=0
  while IFS= read -r e; do [ -n "$e" ] || continue; nexit=$((nexit + 1)); case "$e" in 'exit "$rc"' | 'exit $?' | 'exit 16') : ;; *) CENSUS_WHY="exit [$e]"; bad=1 ;; esac; done < <(tr '\t' '\n' <<< "$exits")
  [ "$nexit" = 4 ] || { CENSUS_WHY="exit statements=$nexit"; bad=1; }
  [ "$rets" = "return 0" ] || { CENSUS_WHY="returns [$rets]"; bad=1; }
  [ "$fd4" = 1 ] || { CENSUS_WHY="fd4 writes=$fd4"; bad=1; }
  return "$bad"
}
CENSUS_WHY=""
if census_ok "$SCRIPT"; then ok "CEN1 static census: every command word of the script is in the closed read-only set ($CMD_ALLOWED), every write redirect is one of the ten known forms, there is exactly ONE write to fd 4 and ONE return 0, and exit appears only as exit 16 / exit \"\$rc\" / exit \$?"; else no "CEN1 static census of the script: $CENSUS_WHY"; fi
# the census must be able to see: a known-positive on a planted script and the instrument's own reach
_cp="$T/census-probe.sh"; printf '#!/bin/bash\ntouch /x\n: > /y\nprintf z >&4\nexit 0\n' > "$_cp"
_co="$(census "$_cp")"
if grep -q '^CMDS .*touch' <<< "$_co" && grep -q '^REDIRS .*>/y' <<< "$_co" && grep -q '^EXITS exit 0$' <<< "$_co" && grep -q '^FD4 1$' <<< "$_co"; then ok "CEN2 harness: the census sees a planted command word, redirect, exit and fd-4 write (it can fail)"; else no "CEN2 the census missed a planted construct: $_co"; fi

# the store mount and the worktree-id charset are the SAME facts the runner and the fence hold: parity, not a second typing
par_mount_ok() { # <host script> <runner>
  local a b
  a="$(sed -n 's/^  readonly RA_MOUNT=//p' "$1")"; b="$(sed -n 's/^OLD_ROOT="${OLD_ROOT:-\([^}]*\)}".*$/\1/p' "$2")"
  [ -n "$a" ] && [ "$a" = "$b" ]
}
par_charset_ok() { # <host script> — the id class of the host regex equals the class the pre-receive fence admits
  local a b
  a="$(sed -n 's/.*refs\/soleur\/worktrees\/(\[\([^]]*\)\]+)\/(heads|tags).*/\1/p' "$1" | head -n 1)"
  b="$(sed -n 's/^  (\*\[!\([^]]*\)\]\*) reject "worktree-id has unsafe characters.*/\1/p' "$DIR/git-data-pre-receive.sh")"
  [ -n "$a" ] && [ "$a" = "$b" ]
}
if par_mount_ok "$SCRIPT" "$CUTOVER"; then ok "PAR10 the host script's RA_MOUNT equals the runner's OLD_ROOT default (/mnt/git-data)"; else no "PAR10 RA_MOUNT and OLD_ROOT drifted"; fi
if par_charset_ok "$SCRIPT"; then ok "PAR11 the worktree-id class of the host regex equals the class the pre-receive fence admits (A-Za-z0-9._-)"; else no "PAR11 id charset drifted from git-data-pre-receive.sh"; fi

echo "--- tier A: Guard 1 and Guard 2 mutation matrices"
SCAN_ON=0
HS_SRC="$SCRIPT"
# G1#1 drop the heads requirement (accept tags-only)
if mutate g1-no-heads-requirement "$HS_SRC" 's#^(  \[ "\$heads" -ge 1 \] \|\| die 24 refs_no_branch_tip)$#  :#'; then mutant_red g1-1-tags-only-accepted case_tags_only "$MUT"; fi
# G1#2 the loop stops after the first compliant ref
if mutate g1-loop-stops "$HS_SRC" 's#^( +ids\["\$id"\]=1)$#\1; break#'; then mutant_red g1-2-loop-stops-after-first case_hostile_name "$MUT" 0; fi
# G1#4 drop %(objecttype) / %(*objecttype) from the format
if mutate g1-drop-objecttype "$HS_SRC" 's#%09%\(objecttype\)##'; then mutant_red g1-4a-no-objecttype case_happy "$MUT"; fi
if mutate g1-drop-peeltype "$HS_SRC" 's#%09<%\(\*objecttype\)>##'; then mutant_red g1-4b-no-peeled-type case_happy "$MUT"; fi
# G1#5 raise the bound
if mutate g1-raise-bound "$HS_SRC" 's#RA_BOUND=200#RA_BOUND=400#'; then mutant_red g1-5-bound-raised case_201 "$MUT"; fi
# G1#6 precondition satisfied, property failed: a nonzero git is not a pass
if mutate g1-ignore-git-rc "$HS_SRC" 's#^(  \[ "\$grc" -eq 0 \] \|\| die 26 refs_unreadable)$#  :#'; then mutant_red g1-6-git-failure-ignored case_missing_object "$MUT"; fi
# G1#7 drop the repositories-directory identity check
if mutate g1-no-dir-identity "$HS_SRC" 's#^(  \[ "\$real" = "\$RA_MOUNT/repositories" \] \|\| die 21 repositories_dir_not_plain)$#  :#'; then mutant_red g1-7-dir-identity-dropped case_store_parent_link "$MUT"; fi
# the stderr rule, the shape order, the shallow refusal, the stdin redirect, the TOCTOU recheck
if mutate g1-stderr-rule "$HS_SRC" 's#^(  \[ ! -s "\$sd/err" \] \|\| die 27 refs_shape_failed)$#  :#'; then mutant_red g1-stderr-rule-dropped case_broken_loose "$MUT"; fi
if mutate g1-shallow "$HS_SRC" 's#^(  \[ -z "\$shl" \] \|\| die 26 refs_unreadable)$#  :#'; then mutant_red g1-shallow-dropped case_shallow "$MUT"; fi
if mutate g1-stdin-redirect "$HS_SRC" 's#^(  exec 3>&2 4>&1 1>/dev/null 2>/dev/null) </dev/null$#\1#'; then mutant_red g1-stdin-redirect-removed case_stdin "$MUT"; fi
if mutate g1-toctou "$HS_SRC" 's#^(  \[ "\$id1" = "\$id0" \] && \[ "\$rid1" = "\$rid0" \] \|\| die 16 identity_changed)$#  :#'; then mutant_red g1-toctou-recheck-dropped case_toctou "$MUT"; fi
if mutate g1-order "$HS_SRC" 's#^(  \[ "\$bad_shape" = 0 \] \|\| die 27 refs_shape_failed)$#  [ "$bad_sha" = 0 ] || die 28 refs_bad_sha#'; then mutant_red g1-order-28-before-27 case_order_27_before_28 "$MUT"; fi
# the hardening flags the runuser shim pins
if mutate g1-safe-directory "$HS_SRC" 's#-c core\.pager=cat#-c core.pager=cat -c safe.directory=*#'; then mutant_red g1-safe-directory-added case_happy "$MUT"; fi
if mutate g1-no-replace "$HS_SRC" 's# GIT_NO_REPLACE_OBJECTS=1##'; then mutant_red g1-no-replace-objects-dropped case_happy "$MUT"; fi
if mutate g1-home "$HS_SRC" 's#HOME=/nonexistent#HOME=/root#'; then mutant_red g1-home-changed case_happy "$MUT"; fi
if mutate g1-answer-fds "$HS_SRC" 's# 3>&- 4>&-##'; then mutant_red g1-answer-fds-open-in-child case_happy "$MUT"; fi
# the cap and the sort self-check
if mutate g1-cap-raised "$HS_SRC" 's#RA_CAP=2#RA_CAP=3#'; then mutant_red g1-cap-raised-to-3 case_cap "$MUT"; fi
if mutate g1-sort-compare "$HS_SRC" 's#^(  \[ "\$\{\#sorted\[@\]\}" -eq "\$\{\#hs\[@\]\}" \] \|\| die 26 refs_unreadable)$#  :#'; then mutant_red g1-sort-truncation-undetected case_sort_trunc "$MUT"; fi
# the count is decided before any ref is read
if mutate g1-read-before-count "$HS_SRC" 's#^(  \[ "\$nrepo" -le 1 \] \|\| die 21 repos_not_single "repos=\$nrepo")$#  :#'; then mutant_red g1-two-repos-accepted case_two_repos "$MUT"; fi
# G2#1 a refname or the repository basename reaches an answer fd on a refusal
if mutate g2-echo-name "$HS_SRC" 's#^(  die\(\) \{ local rc="\$1"; shift;)#\1 [ -z "${ra_dbg-}" ] \&\& printf "%s %s\\n" "${ref-}" "${name-}" >\&3;#'; then mutant_red g2-1-name-echoed-on-refusal case_hostile_name "$MUT" 0; fi
for _vb in $WRITE_VERBS_PATH; do
  case "$_vb" in
    rm) _ins='rm -rf -- /var/lib/x' ;; chown) _ins='chown root:root /x' ;; mount) _ins='mount -o remount,rw /mnt/git-data' ;; systemctl) _ins='systemctl stop git-data-gc.timer' ;;
  esac
  if mutate "g2-write-$_vb" "$HS_SRC" "s#^(  exec 3>&2 4>&1 1>/dev/null 2>/dev/null)#  $_ins\n\1#"; then mutant_red "g2-2-write-verb-$_vb-fires" case_happy "$MUT"; fi
done
for _vb in $WRITE_VERBS_GIT; do
  if mutate "g2-write-git-$_vb" "$HS_SRC" "s# for-each-ref --count=[^']* --format='[^']*' refs/soleur/worktrees/# $_vb refs/soleur/worktrees/#"; then mutant_red "g2-2-write-verb-git-$_vb-refused" case_happy "$MUT"; fi
done

# nth-occurrence mutation: mutate_nth <name> <src> <k> <literal> <replacement> — the k-th occurrence of the literal text
mutate_nth() {
  MUT="$T/mut/$1"
  awk -v k="$3" -v lit="$4" -v rep="$5" '{ line = $0; out = ""; while ((i = index(line, lit)) > 0) { c++; out = out substr(line, 1, i - 1) (c == k ? rep : lit); line = substr(line, i + length(lit)) } print out line }' "$2" > "$MUT"
  if cmp -s "$2" "$MUT"; then no "mutation $1: the awk edit did not change the file (the row would prove nothing)"; return 1; fi
  return 0
}
# new guards of the 12-seat review (F23, F24, F29-adjacent host fixes): each mutant must be caught by its named row
if mutate g3-owner-check "$HS_SRC" 's#^(  \[ "\$\{rid0\#\#\*:\}" = git \] \|\| die 27 repo_owner)$#  :#'; then mutant_red g3-1-owner-check-dropped case_foreign_owner "$MUT"; fi
if mutate g3-owner-recheck "$HS_SRC" 's#\[ "\$rid1" = "\$rid0" \]#[ "${rid1%:*}" = "${rid0%:*}" ]#'; then mutant_red g3-2-owner-ignored-in-recheck case_owner_flip "$MUT"; fi
if mutate g3-alternates "$HS_SRC" 's#^(  case "\$lnk" in \*a\*\) die 27 repo_alternates ;; esac)$#  :#'; then mutant_red g3-3-alternates-refusal-dropped case_all case_alternates "$MUT" alternates http-alternates symlink; fi
if mutate g3-http-alternates "$HS_SRC" 's# -o -path "\$repo/objects/info/http-alternates"##'; then mutant_red g3-4-http-alternates-not-probed case_all case_alternates "$MUT" http-alternates; fi
if mutate g3-symlink-refusal "$HS_SRC" 's#^(  case "\$lnk" in \*s\*\) die 27 repo_symlink ;; esac)$#  :#'; then mutant_red g3-5-symlink-refusal-dropped case_all case_symlink "$MUT" refs-soleur deep-ref root-entry objects-entry objects-file packed-refs; fi
if mutate g3-symlink-pred "$HS_SRC" 's# -type l -printf s -o##'; then mutant_red g3-6-symlink-predicate-dropped case_all case_symlink "$MUT" refs-soleur deep-ref root-entry objects-entry objects-file packed-refs; fi
if mutate g3-prune-shallow "$HS_SRC" 's#-path "\$repo/objects/\*/\*" -prune#-path "$repo/objects/*" ! -path "$repo/objects/info" -prune#'; then mutant_red g3-7-prune-too-early-misses-objects-depth-2 case_symlink "$MUT" objects-file; fi
if mutate g3-symref-refusal "$HS_SRC" 's#^(  \[ -z "\$lnk" \] \|\| die 27 ref_symref)$#  :#'; then mutant_red g3-8-on-disk-symref-refusal-dropped case_all case_symref "$MUT" dangling dangling-alone dangling-nested live; fi
if mutate g3-size-pred "$HS_SRC" 's# -o \\\( -path "\$repo/refs/soleur/worktrees/\*" -type f ! -size 41c ! -name .\*\.lock. -printf f \\\)##'; then mutant_red g3-9-size-probe-dropped case_symref "$MUT" dangling; fi
if mutate g3-lock-excl "$HS_SRC" "s# ! -name '\\*\\.lock'##"; then mutant_red g3-10-lock-files-counted-as-refs case_lockfile_ok "$MUT"; fi
if mutate g3-symref-flag "$HS_SRC" 's#bad_sym=1; else bad_shape=1; fi#:; else bad_shape=1; fi#'; then mutant_red g3-11-symref-field-ignored case_fake_symref_field "$MUT"; fi
if mutate g3-sentinel "$HS_SRC" 's#else bad_shape=1; continue; fi#else :; fi#; s#else bad_shape=1; fi#else :; fi#'; then mutant_red g3-12-sentinel-enforcement-dropped case_all case_fake_collapsed "$MUT" four empty; fi
if mutate g3-shallow-probe "$HS_SRC" 's# \|\| die 16 shallow_probe##'; then mutant_red g3-13-shallow-probe-failure-ignored case_find_fail_shallow "$MUT"; fi
if mutate g3-shape-probe "$HS_SRC" 's# \|\| die 16 shape_probe##'; then mutant_red g3-14-shape-probe-failure-ignored case_find_fail_shape "$MUT"; fi
if mutate g3-enum "$HS_SRC" 's#^(  \[ "\$saw_end" = 1 \] \|\| die 16 enumeration_failed)$#  :#'; then mutant_red g3-15-failed-find-on-empty-store-reads-as-absent case_find_fail_empty "$MUT"; fi
for _k in 1 2 3 4 5 6; do
  if mutate_nth "g3-stat-$_k" "$HS_SRC" "$_k" ' || die 16 stat_failed' ''; then mutant_red "g3-16-stat-site-$_k-failure-ignored" case_stat_fail "$MUT" "$_k"; fi
done
if mutate g3-toctou-repos "$HS_SRC" 's#\[ "\$id1" = "\$id0" \] && ##'; then mutant_red g3-17-repositories-dir-swap-undetected case_toctou_repos "$MUT"; fi
if mutate g3-trap "$HS_SRC" "/^  trap 'exit 16' HUP INT TERM PIPE\$/d"; then mutant_red g3-18-signal-trap-removed case_term "$MUT"; fi
if mutate g3-stderr-redirect "$HS_SRC" 's#^(  exec 3>&2 4>&1 1>/dev/null) 2>/dev/null </dev/null$#\1 </dev/null#'; then mutant_red g3-19-stderr-discard-removed case_noisy "$MUT"; fi
if mutate g3-stdout-redirect "$HS_SRC" 's#^(  exec 3>&2 4>&1) 1>/dev/null (2>/dev/null </dev/null)$#\1 \2#'; then mutant_red g3-20-stdout-discard-removed case_noisy "$MUT"; fi
if mutate g3-cleanup "$HS_SRC" 's#if \[ -n "\$sd" \]; then rm -f -- "\$sd/err"; rmdir -- "\$sd"; fi;#:;#'; then mutant_red g3-21-scratch-cleanup-dropped case_happy "$MUT"; fi
if mutate g3-dot-id "$HS_SRC" 's#\[ "\$id" = \. \] \|\| ##'; then mutant_red g3-22-id-dot-accepted case_fake_dot1 "$MUT"; fi
# argv and census guards: a command or flag the shims do not model must still be RED
if mutate g3-find-delete "$HS_SRC" 's#-name shallow -printf x#-name shallow -delete -printf x#'; then mutant_red g3-23-find-delete-recorded case_happy_argv "$MUT"; fi
if mutate g3-mktemp-argv "$HS_SRC" 's#mktemp -d -p /dev/shm#mktemp -d -p /dev/shm/#'; then mutant_red g3-24-mktemp-argv-changed case_happy_argv "$MUT"; fi
if mutate g3-readlink-argv "$HS_SRC" 's#readlink -f --#readlink -m --#'; then mutant_red g3-25-readlink-argv-changed case_happy_argv "$MUT"; fi
if mutate g3-stat-argv "$HS_SRC" 's#stat -c %m --#stat -L -c %m --#'; then mutant_red g3-26-stat-argv-changed case_happy_argv "$MUT"; fi
_ins_line() { echo "s#^(  exec 3>\&2 4>\&1 1>/dev/null 2>/dev/null) </dev/null\$#  $1\n\1 </dev/null#"; }
if mutate g3-census-cmd "$HS_SRC" "$(_ins_line 'date >/dev/null')"; then mutant_red g3-27-unknown-command-word census_ok "$MUT"; fi
if mutate g3-census-redirect "$HS_SRC" "$(_ins_line ': > /mnt/git-data/x')"; then mutant_red g3-28-file-redirect census_ok "$MUT"; fi
if mutate g3-census-fd4 "$HS_SRC" "$(_ins_line '[ -e /x ] \&\& { printf z >\&4; exit 16; }')"; then mutant_red g3-29-second-answer-write census_ok "$MUT"; fi
if mutate g3-census-exit "$HS_SRC" "$(_ins_line '[ -e /x ] \&\& exit 29')"; then mutant_red g3-30-extra-exit-path census_ok "$MUT"; fi
if mutate g3-census-return "$HS_SRC" "$(_ins_line '[ -e /x ] \&\& return 0')"; then mutant_red g3-31-extra-return census_ok "$MUT"; fi
if mutate g3-census-cmd-touch "$HS_SRC" "$(_ins_line 'touch /mnt/git-data/x')"; then mutant_red g3-32-touch-written-to-store census_ok "$MUT"; fi
if mutate g3-mount "$HS_SRC" 's#readonly RA_MOUNT=/mnt/git-data#readonly RA_MOUNT=/mnt/git-data2#'; then mutant_red g3-34-mount-drift par_mount_ok "$MUT" "$CUTOVER"; fi
if mutate g3-charset "$HS_SRC" 's#\(\[A-Za-z0-9\._-\]\+\)/\(heads\|tags\)#([A-Za-z0-9._+-]+)/(heads|tags)#'; then mutant_red g3-35-id-charset-drift par_charset_ok "$MUT"; fi
for _vb in touch mkdir; do
  case "$_vb" in touch) _ins='touch /mnt/git-data/x' ;; mkdir) _ins='mkdir /mnt/git-data/x' ;; esac
  if mutate "g3-write-$_vb" "$HS_SRC" "s#^(  exec 3>&2 4>&1 1>/dev/null 2>/dev/null)#  $_ins\n\1#"; then mutant_red "g3-33-write-verb-$_vb-fires" case_happy "$MUT"; fi
done

SCAN_ON=1
echo "--- print scan over every tier-A run"
if [ "${#SCAN_FAILS[@]}" = 0 ] && [ "$SCAN_RUNS" -ge 50 ]; then ok "SCAN no fixture repository, worktree or branch name and no stray sha reached stdout or stderr in any of $SCAN_RUNS tier-A runs"; else no "SCAN leaks or too few runs ($SCAN_RUNS): ${SCAN_FAILS[*]}"; fi
TIERA_SCAN_RUNS=$SCAN_RUNS

# ══════════════════════════════════════════════════════════════════════════════════════════
# Tier B — the verb
# ══════════════════════════════════════════════════════════════════════════════════════════
echo "--- tier B: git-data-cutover.sh MODE=refs_assert"
SB="$T/sshshim"; assert_fixture_dir "$SB"; mkdir -p "$SB" || instrument "mkdir sshshim failed"
cat > "$SB/ssh" <<'SSHSHIM'
#!/usr/bin/env bash
# Answers by the remote COMMAND text. $TL is the per-row log directory.
last="${*: -1}"
printf 'ssh\n' >> "$TL/calls"
case " $* " in *" -W "*) echo "SSH-2.0-OpenSSH_9.6"; exit 0 ;; esac
[ "$last" = true ] && exit 0
case "$last" in
  "findmnt -n -o SOURCE --mountpoint"*)
    printf 'findmnt\n' >> "$TL/seq"
    [ -f "$TL/findmnt_rc" ] && exit "$(cat "$TL/findmnt_rc")"
    cat "$TL/source" 2>/dev/null || echo /dev/mapper/git-data; exit 0 ;;
  "r="*)
    printf 'verify\n' >> "$TL/seq"
    rc="$(cat "$TL/verify_rc" 2>/dev/null || echo 0)"; [ "$rc" = 0 ] && echo 0; exit "$rc" ;;
  "fz="*)
    printf 'freeze-probe\n' >> "$TL/seq"; echo absent; exit 0 ;;
  "REFS_REPOS="*)
    printf 'refs\n' >> "$TL/seq"
    printf '%s\n' "$last" > "$TL/cmd"
    cat > "$TL/stdin"
    [ -f "$TL/hang" ] && sleep 20
    if [ -f "$TL/deliver" ]; then
      # END TO END: the real body through a real `bash -s` over the tier-A world, exactly as production runs it
      exec env -i PATH="$SHIMDIR:/usr/bin:/bin" HOME="$WORLD/home" WORLD="$WORLD" REALGIT="$REALGIT" bash -c "$last" < "$TL/stdin"
    fi
    [ -f "$TL/answer" ] && cat "$TL/answer"
    [ -z "${SHIM_ERR:-}" ] || printf '%s\n' "$SHIM_ERR" >&2
    exit "$(cat "$TL/rc")" ;;
esac
printf 'unexpected\t%s\n' "$last" >> "$TL/unexpected"
exit 97
SSHSHIM
cat > "$SB/timeout" <<'TOSHIM'
#!/usr/bin/env bash
SD="${0%/*}"
REAL="$(PATH="${PATH#"$SD":}" command -v timeout)"
printf '%s\n' "$1" >> "$TL/timeouts"
if [ -f "$TL/hang" ] && [ "$1" = 60 ]; then shift; exec "$REAL" 2 "$@"; fi
exec "$REAL" "$@"
TOSHIM
chmod +x "$SB/ssh" "$SB/timeout" || instrument "chmod sshshim failed"

VRC=0; TL=""
VERB_SCAN_RUNS=0
# run_verb <label> <answer-line|-> <rc> [VAR=value ...]
run_verb() {
  local label="$1" answer="$2" rc="$3"; shift 3
  TL="$T/tl-$label"; assert_fixture_dir "$TL"; rm -rf "$TL"; mkdir -p "$TL" || instrument "mkdir $TL failed"
  : > "$TL/calls"; : > "$TL/timeouts"; : > "$TL/seq"; printf '%s' "$rc" > "$TL/rc"
  if [ "$answer" != "-" ]; then printf '%s\n' "$answer" > "$TL/answer"; fi
  : > "$TL/gh_output"; : > "$TL/gh_summary"
  local -a ev=(); local a _n
  for a in "$@"; do
    case "$a" in @*=*) _n="${a#@}"; printf '%s' "${a#*=}" > "$TL/${_n%%=*}" ;; *) ev+=("$a") ;; esac
  done
  VRC=0
  env -i PATH="$SB:/usr/bin:/bin" HOME="$T" TL="$TL" MODE=refs_assert \
    GIT_DATA_SSH="ssh -F /dev/null" WEB_HOST_SSH="ssh -F /dev/null" \
    GITHUB_OUTPUT="$TL/gh_output" GITHUB_STEP_SUMMARY="$TL/gh_summary" \
    "${ev[@]}" bash "$CUTOVER" > "$TL/out" 2> "$TL/err" || VRC=$?
  [ "$SCAN_ON" = 1 ] || return 0
  VERB_SCAN_RUNS=$((VERB_SCAN_RUNS + 1))
  local sr=0; scan_files "$TL/out" "$TL/err" "$TL/gh_summary" "$TL/gh_output" || sr=$?
  [ "$sr" = 0 ] || SCAN_FAILS+=("verb:$label(rc=$sr)")
}
GOOD="$(ANS 1 1 1 "$C1")"
has_store() { grep -qxF "[git-data-cutover] STORE probe=refs-assert verdict=$1" "$TL/out"; }
has_line() { grep -qxF -- "$1" "$TL/out"; }
no_refs_session() { [ ! -e "$TL/cmd" ] && ! grep -qx refs "$TL/seq"; }
cls_ok() { # <word> <class> [suffix] — the annotation, the summary line and GITHUB_OUTPUT
  has_line "::error title=git-data-cutover refs::verdict=$1 class=$2${3:+ $3}" \
    && grep -qxF -- "- REFS verdict=$1 class=$2${3:+ $3}" "$TL/gh_summary" \
    && [ "$(cat "$TL/gh_output")" = "refs_class=$2" ]
}

run_verb b01 "$GOOD" 0
if [ "$VRC" = 0 ] && has_store ok && has_line "[git-data-cutover] REFS-CONFIRMED" && has_line "[git-data-cutover] REFS_ASSERT ${GOOD#refs_assert }" \
   && grep -qxF -- "- REFS-CONFIRMED" "$TL/gh_summary" && grep -qxF -- "- REFS_ASSERT ${GOOD#refs_assert }" "$TL/gh_summary" \
   && has_line "::notice title=git-data-cutover store::probe=refs-assert verdict=ok"; then
  ok "B01 pass: exit 0, STORE probe=refs-assert verdict=ok, REFS-CONFIRMED and the REFS_ASSERT line in the log and the step summary"
else no "B01 pass: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-400)]"; fi
if [ ! -s "$TL/gh_output" ]; then ok "B01b the success path writes NOTHING to GITHUB_OUTPUT"; else no "B01b success wrote GITHUB_OUTPUT: $(cat "$TL/gh_output")"; fi
if cmp -s "$SCRIPT" "$TL/stdin"; then ok "B02 the host script is sent on STDIN, byte for byte (the single ssh site, gd_capture)"; else no "B02 the stdin of the remote call is not the host script"; fi
if [ "$(cat "$TL/cmd")" = "REFS_REPOS=/mnt/git-data/repositories bash -s" ]; then ok "B03 the remote command is exactly the %q-quoted REFS_REPOS in front of 'bash -s'"; else no "B03 remote command differs: [$(cat "$TL/cmd")]"; fi
if [ "$(paste -sd' ' "$TL/timeouts")" = "30 25 30 30 30 60" ]; then ok "B04 bounds: access gate 30/25/30, the two store reads 30, the refs session 60 s"; else no "B04 bounds differ: [$(paste -sd' ' "$TL/timeouts")]"; fi
if [ "$(paste -sd' ' "$TL/seq")" = "findmnt verify refs" ]; then ok "B05 order: unmounted/mapper probe, the verified-only store session, THEN the refs session (no freeze probe: a held freeze refuses)"; else no "B05 order: [$(paste -sd' ' "$TL/seq")]"; fi
run_verb b06 "$GOOD" 0 "OLD_ROOT=/mnt/git-data" "REPO_SUBDIR=repositories"
if [ "$VRC" = 0 ] && [ "$(cat "$TL/cmd")" = "REFS_REPOS=/mnt/git-data/repositories bash -s" ]; then ok "B06 the sent path is OLD_ROOT/REPO_SUBDIR, %q-quoted"; else no "B06 sent path: rc=$VRC cmd=[$(cat "$TL/cmd")]"; fi

echo "--- rc -> word and class (the table is the host script's header)"
declare -A WORD=([20]=refs_repo_absent [21]=refs_repo_not_single [23]=refs_none [24]=refs_no_branch_tip [26]=refs_unreadable [28]=refs_bad_sha)
declare -A CLASS=([refs_repo_absent]=FAILED [refs_repo_not_single]=INCONCLUSIVE [refs_none]=FAILED [refs_no_branch_tip]=FAILED [refs_unreadable]=INCONCLUSIVE [refs_bad_sha]=FAILED)
for rc in 20 21 23 24 26 28; do
  run_verb "r$rc" - "$rc"
  w="${WORD[$rc]}"
  if [ "$VRC" = 5 ] && has_store "$w" && cls_ok "$w" "${CLASS[$w]}"; then ok "RC $rc -> exit 5, verdict=$w class=${CLASS[$w]} (annotation, summary and refs_class output)"
  else no "RC $rc: expected $w ${CLASS[$w]}; rc=$VRC out=[$(grep -E 'STORE|refs' "$TL/out" | tr '\n' '|' | cut -c1-300)] gho=[$(cat "$TL/gh_output")]"; fi
done
run_verb r27 - 27
if [ "$VRC" = 5 ] && has_store "refs_shape_failed rc=27" && cls_ok refs_shape_failed INCONCLUSIVE "rc=27"; then ok "RC 27 -> refs_shape_failed class=INCONCLUSIVE with the fixed rc=27 suffix"; else no "RC 27: rc=$VRC out=[$(grep -E 'STORE|refs' "$TL/out" | tr '\n' '|' | cut -c1-300)]"; fi
run_verb r96 "refs_assert ok repos=2 namespaces=1 refs=1 heads=1 shas=$C1" 0
if [ "$VRC" = 5 ] && has_store "refs_shape_failed rc=96" && cls_ok refs_shape_failed INCONCLUSIVE "rc=96"; then ok "RC 96 -> an off-shape answer is refs_shape_failed rc=96 (shares the word with rc 27)"; else no "RC 96: rc=$VRC out=[$(grep -E 'STORE|refs' "$TL/out" | tr '\n' '|' | cut -c1-300)]"; fi
for rc in 16 124 255 7 97; do
  run_verb "t$rc" - "$rc"
  if [ "$VRC" = 5 ] && has_store "probe_failed rc=$rc" && cls_ok probe_failed INCONCLUSIVE; then ok "RC $rc (instrument or transport) -> probe_failed rc=$rc class=INCONCLUSIVE, never a host verdict"; else no "RC $rc: rc=$VRC out=[$(grep -E 'STORE|refs' "$TL/out" | tr '\n' '|' | cut -c1-300)]"; fi
done
run_verb r21b - 21 SHIM_ERR="refs-assert: rc=21 reason=repos_not_single repos=2"
if [ "$VRC" = 5 ] && grep -qxF "[git-data-cutover] probe-stderr: refs-assert: rc=21 reason=repos_not_single repos=2" "$TL/out" && has_line "::error title=git-data-cutover refs::verdict=refs_repo_not_single class=INCONCLUSIVE repos=2"; then ok "RC 21 relays the digits-only stderr behind one probe-stderr prefix and the annotation carries repos=2 only after a regex match"; else no "RC 21 stderr relay: $(tr '\n' '|' < "$TL/out" | cut -c1-400)"; fi
run_verb r21c - 21 SHIM_ERR="refs-assert: rc=21 reason=repos_not_single repos=2; ::add-mask::x"
if [ "$VRC" = 5 ] && ! has_line "::error title=git-data-cutover refs::verdict=refs_repo_not_single class=INCONCLUSIVE repos=2" && has_line "::error title=git-data-cutover refs::verdict=refs_repo_not_single class=INCONCLUSIVE" && ! grep -qE '^::add-mask::' "$TL/out"; then ok "RC 21 a hostile stderr never becomes repos=<n>, and no workflow command survives the relay"; else no "RC 21 hostile stderr: $(tr '\n' '|' < "$TL/out" | cut -c1-400)"; fi
run_verb r27b - 27 SHIM_ERR=$'::error::forged\n::stop-commands::x\n::add-mask::y'
if [ "$VRC" = 5 ] && ! grep -qE '^::(error::forged|add-mask::)' "$TL/out" && grep -q '::stop-commands::' "$TL/out"; then ok "RC 27 hostile stderr (::error::, ::stop-commands::, ::add-mask::) is wrapped and filtered: no workflow command survives"; else no "RC 27 hostile stderr: $(tr '\n' '|' < "$TL/out" | cut -c1-400)"; fi
run_verb b20 - 0 @hang=1
if [ "$VRC" = 5 ] && has_store "probe_failed rc=124" && cls_ok probe_failed INCONCLUSIVE; then ok "B20 a hung session is cut by the explicit 60 s bound -> probe_failed rc=124"; else no "B20 timeout: rc=$VRC out=[$(grep -E 'STORE|refs' "$TL/out" | tr '\n' '|' | cut -c1-300)]"; fi

echo "--- off-shape answers are refused, the value is never printed"
for ans in "$GOOD extra" "refs_assert ok repos=0 namespaces=1 refs=1 heads=1 shas=$C1" "refs_assert ok repos=1 namespaces=0 refs=1 heads=1 shas=$C1" \
           "refs_assert ok repos=1 namespaces=1 refs=0 heads=1 shas=$C1" "refs_assert ok repos=1 namespaces=1 refs=1 heads=0 shas=$C1" \
           "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=" "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=$C1,$C2,$C3" \
           "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=${C1^^}" "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=${C1:0:39}" \
           "refs_assert ok repos=01x namespaces=1 refs=1 heads=1 shas=$C1" "wipe_assert pre ok layout_signal=ok"; do
  run_verb forged "$ans" 0
  if [ "$VRC" = 5 ] && has_store "refs_shape_failed rc=96" && ! grep -qF -- "$ans" "$TL/out" && ! grep -q 'REFS-CONFIRMED' "$TL/out"; then ok "B21 forged answer [${ans:0:60}] -> refs_shape_failed rc=96, not printed, no REFS-CONFIRMED"; else no "B21 forged answer accepted or printed: [${ans:0:60}] rc=$VRC"; fi
done
# positive pins of the anchored pattern: multi-digit counts and the 40-hex pair are ACCEPTED (a pattern that narrows them is RED)
for ans in "refs_assert ok repos=1 namespaces=12 refs=200 heads=105 shas=$C1,$C2" "refs_assert ok repos=1 namespaces=1 refs=10 heads=10 shas=$C1"; do
  run_verb b21p "$ans" 0
  if [ "$VRC" = 0 ] && has_line "[git-data-cutover] REFS-CONFIRMED" && has_line "[git-data-cutover] REFS_ASSERT ${ans#refs_assert }"; then ok "B21p accepted [${ans:0:70}]: multi-digit counts are not narrowed by the pattern"; else no "B21p a valid multi-digit answer was refused: [${ans:0:70}] rc=$VRC"; fi
done
# negative pins: leading junk, a 41-hex sha among otherwise valid answers
for ans in "X$GOOD" " $GOOD" "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=${C1}0" "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=$C1,${C2}0"; do
  run_verb b21n "$ans" 0
  if [ "$VRC" = 5 ] && has_store "refs_shape_failed rc=96" && ! grep -q 'REFS-CONFIRMED' "$TL/out"; then ok "B21n forged answer [${ans:0:40}...] -> refs_shape_failed rc=96 (leading junk and a 41-hex sha are refused)"; else no "B21n forged answer accepted: [${ans:0:40}] rc=$VRC"; fi
done
run_verb b22 "$GOOD
$GOOD" 0
if [ "$VRC" = 5 ] && has_store "refs_shape_failed rc=96"; then ok "B22 a multi-line answer is refused"; else no "B22 multi-line accepted: rc=$VRC"; fi
SH_ONE="refs_assert ok repos=1 namespaces=1 refs=2 heads=2 shas=$C1,$C2"
run_verb b23 "$SH_ONE" 0
if [ "$VRC" = 0 ] && has_line "[git-data-cutover] REFS_ASSERT ${SH_ONE#refs_assert }"; then ok "B23 two shas (the cap) are accepted"; else no "B23 two-sha answer: rc=$VRC"; fi
# the failure path never prints what the host answered (Guard 2 mutation 3)
run_verb b24 "refs_assert ok repos=2 CANARY-ANSWER-7c1e namespaces=1" 0
if [ "$VRC" = 5 ] && ! grep -rq 'CANARY-ANSWER-7c1e' "$TL/out" "$TL/err" "$TL/gh_summary" "$TL/gh_output"; then ok "B24 a rejected answer's text reaches no sink"; else no "B24 a rejected answer was printed"; fi

# the success site: an added empty arm must never read as REFS-CONFIRMED (the host's OWN answer line is required)
run_verb b25 - 29
if [ "$VRC" = 5 ] && has_store "probe_failed rc=29" && ! grep -q 'REFS-CONFIRMED' "$TL/out"; then ok "B25 an unlisted rc (29) with no output is probe_failed rc=29, never a pass"; else no "B25 rc 29: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)]"; fi
# empty-bodied arms of the verb's case, derived from the source: the ONLY one is the pass arm `0)`
empty_arms() { python3 - "$1" <<'PY'
import re, sys
fn = open(sys.argv[1]).read().split("mode_refs_assert() {", 1)[1].split("\n}\n", 1)[0]
case = fn.split('case "$rc" in', 1)[1].split("esac", 1)[0]
print(" ".join(sorted(a for a, b in re.findall(r"^\s+([0-9*]+)\)\s*(.*)$", case, re.M) if re.fullmatch(r"(;;)?", b.strip()))))
PY
}
if [ "$(empty_arms "$CUTOVER")" = "0" ]; then ok "B26 the only empty-bodied arm of mode_refs_assert's rc case is the pass arm 0) (derived from the source)"; else no "B26 empty-bodied arms: [$(empty_arms "$CUTOVER")]"; fi

echo "--- runner-side refusals: the script is never sent, the class is INCONCLUSIVE"
run_verb c01 - 0 @verify_rc=23
if [ "$VRC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=store-verified verdict=cutover_frozen" "$TL/out" && no_refs_session && has_line "::error title=git-data-cutover refs::verdict=cutover_frozen class=INCONCLUSIVE" && [ "$(cat "$TL/gh_output")" = "refs_class=INCONCLUSIVE" ] && ! grep -qx freeze-probe "$TL/seq"; then
  ok "C01 a held freeze refuses cutover_frozen (no bypass, no same-lineage tolerance), INCONCLUSIVE, the script never sent"
else no "C01 cutover_frozen: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-400)] gho=[$(cat "$TL/gh_output")]"; fi
for pair in "source:tmpfs:old_store_unmounted" "source:/dev/sdb1:store_not_on_mapper" "verify:21:store_unverified" "verify:22:store_unverified" "verify:24:store_unverified" "verify:5:probe_failed" "verify:6:probe_failed"; do
  kind="${pair%%:*}"; rest="${pair#*:}"; val="${rest%:*}"; want="${rest##*:}"
  run_verb c02 - 0 "@$kind$([ "$kind" = verify ] && echo _rc)=$val"
  if [ "$VRC" = 5 ] && grep -qE "^\[git-data-cutover\] STORE probe=store-[a-z-]+ verdict=$want" "$TL/out" && no_refs_session && grep -qE "^::error title=git-data-cutover refs::verdict=$want class=INCONCLUSIVE" "$TL/out" && [ "$(cat "$TL/gh_output")" = "refs_class=INCONCLUSIVE" ]; then
    ok "C02 runner-side $pair -> $want, INCONCLUSIVE, the script never sent"
  else no "C02 $pair: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)] gho=[$(cat "$TL/gh_output")]"; fi
done
run_verb c03 - 0 GIT_DATA_SSH=
if [ "$VRC" = 3 ] && no_refs_session && has_line "::error title=git-data-cutover refs::verdict=access_refused class=INCONCLUSIVE" && grep -qxF -- "- REFS verdict=access_refused class=INCONCLUSIVE" "$TL/gh_summary" && [ "$(cat "$TL/gh_output")" = "refs_class=INCONCLUSIVE" ]; then ok "C03 no root credential: the access gate refuses (exit 3) before any store probe, and the refusal still carries the documented word access_refused and class INCONCLUSIVE (annotation, summary, output)"; else no "C03 access gate: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)] gho=[$(cat "$TL/gh_output")]"; fi
run_verb c04 "$GOOD" 0 'OLD_ROOT=/mnt/x;touch /y'
if [ "$VRC" = 5 ] && grep -qF 'reason=arg_root' "$TL/out" && [ ! -s "$TL/calls" ]; then ok "C04 an unsafe OLD_ROOT is refused by the shared config check before any host is dialed"; else no "C04 unsafe OLD_ROOT: rc=$VRC calls=$(wc -l < "$TL/calls")"; fi
run_verb c05 "$GOOD" 0 MODE=refs_assert_x
if [ "$VRC" = 5 ] && grep -qF 'verdict=mode_invalid' "$TL/out" && [ ! -s "$TL/calls" ]; then ok "C05 a near-miss mode word is still mode_invalid"; else no "C05 MODE=refs_assert_x: rc=$VRC"; fi
for _lg in DRY_RUN=0 ROLLBACK=1 CONFIRM_WIPE=1; do
  run_verb c06 "$GOOD" 0 "$_lg"
  if [ "$VRC" = 5 ] && grep -qF 'verdict=real_cutover_unreconciled' "$TL/out" && grep -qF 'refs_assert' "$TL/out" && [ ! -s "$TL/calls" ]; then ok "C06 legacy env $_lg is still refused, and the remedy names refs_assert"; else no "C06 legacy $_lg: rc=$VRC"; fi
done

echo "--- end to end: the real body through a real bash -s over the tier-A world"
new_world e2e; mkrepo "$REPO"; want_ref "$REPO" "$(nsref "$WT_A" "heads/$BR_A")" "$C1"; want_ref "$REPO" "$(nsref "$WT_B" "heads/$BR_B")" "$C2"
: > "$W/state/runuser_calls"
run_verb e2e - 0 @deliver=1 SHIMDIR="$SH" WORLD="$W" REALGIT="$REALGIT"
_exp="$(printf '%s\n' "$C1" "$C2" | sort | paste -sd, -)"
if [ "$VRC" = 0 ] && has_line "[git-data-cutover] REFS_ASSERT ok repos=1 namespaces=2 refs=2 heads=2 shas=$_exp" && violations; then ok "E01 the body arrives on stdin to a real bash -s with REFS_REPOS in front; the runner accepts the real answer (REFS-CONFIRMED)"; else no "E01 end to end: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-400)] err=[$(head -c 300 "$TL/err")]"; fi
assert_clean e2e-world "$W/state/violations"
mkbare "$REPO2"
run_verb e2e2 - 0 @deliver=1 SHIMDIR="$SH" WORLD="$W" REALGIT="$REALGIT"
if [ "$VRC" = 5 ] && has_store refs_repo_not_single && has_line "::error title=git-data-cutover refs::verdict=refs_repo_not_single class=INCONCLUSIVE repos=2" && ! grep -qF -- "$REPO2" "$TL/out"; then ok "E02 end to end, a second repository: refs_repo_not_single INCONCLUSIVE repos=2 with the name in no sink"; else no "E02 end to end two repos: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-400)]"; fi

echo "--- Guard 1 #3 and Guard 2 #3: the runner's regex and its print discipline"
SCAN_ON=0
if mutate_cutover g1-regex-repos 's/\^refs_assert ok repos=1 namespaces/^refs_assert ok repos=[0-9]+ namespaces/'; then
  case_forged_repos() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m1 "refs_assert ok repos=2 namespaces=1 refs=1 heads=1 shas=$C1" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ]; }
  mutant_red g1-3a-runner-repos-anchor-lost case_forged_repos "$MUT"
fi
if mutate_cutover g1-regex-minima 's/refs=\[1-9\]\[0-9\]\* heads=\[1-9\]\[0-9\]\*/refs=[0-9]+ heads=[0-9]+/'; then
  case_forged_zero() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m2 "refs_assert ok repos=1 namespaces=1 refs=0 heads=0 shas=$C1" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ]; }
  mutant_red g1-3b-runner-minima-lost case_forged_zero "$MUT"
fi
if mutate_cutover g1-no-send 's/gd_capture "\$pat" "\$cmd" "\$body" "\$tmo"/gd_capture "$pat" "$cmd" \/dev\/null "$tmo"/'; then
  case_script_not_sent() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m3 "$GOOD" 0; local r="$VRC"; CUTOVER="$c"; cmp -s "$SCRIPT" "$TL/stdin" && [ "$r" = 0 ]; }
  mutant_red g1-3c-script-not-sent-forged-line-passes case_script_not_sent "$MUT"
fi
if mutate_cutover g2-print-captured 's/^(  if ! \[\[ "\$val" =~ \$pat \]\]; then)$/\1\n    log "answer: $val"/'; then
  case_captured_unprinted() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m4 "refs_assert ok repos=2 CANARY-ANSWER-7c1e namespaces=1" 0; CUTOVER="$c"; ! grep -q 'CANARY-ANSWER-7c1e' "$TL/out"; }
  mutant_red g2-3-answer-printed-on-failure case_captured_unprinted "$MUT"
fi
# the success site (finding A): an extra EMPTY arm falls through; the post-case match must still refuse
case_arm_refused() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m5 - 29; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ] && has_store "refs_shape_failed rc=96" && ! grep -q 'REFS-CONFIRMED' "$TL/out"; }
if mutate_cutover g4-arm29 's/^    0\) ;;$/    0) ;;\n    29) ;;/'; then
  _arm_ctl="$MUT"
  if case_arm_refused "$_arm_ctl"; then ok "B27 control: with an added empty arm 29) ;; the runner STILL refuses (refs_shape_failed rc=96, no REFS-CONFIRMED): success needs the host's own answer line"; else no "B27 an empty arm 29) confirmed or misreported: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)]"; fi
  if [ "$(empty_arms "$_arm_ctl")" = "0 29" ]; then ok "B28 the empty-arm scan sees an added 29) ;; (it can fail)"; else no "B28 the scan missed the planted empty arm: [$(empty_arms "$_arm_ctl")]"; fi
  # the same mutant with the post-case match removed is the shipped defect: the case must go RED
  sed -E -i '/^  \[\[ "\$GD_CAPTURED" =~ \$pat \]\] \|\| _refs_refuse refs_shape_failed 96$/d' "$_arm_ctl"
  if /usr/bin/grep -q 'GD_CAPTURED" =~ \$pat' "$_arm_ctl"; then no "mutation g4-no-postmatch: the post-case match is still present"; else mutant_red g4-1-fallthrough-confirms-with-no-answer case_arm_refused "$_arm_ctl"; fi
fi
case_two_digit() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m6 "refs_assert ok repos=1 namespaces=12 refs=200 heads=105 shas=$C1,$C2" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 0 ]; }
if mutate_cutover g4-refs-digits 's/refs=\[1-9\]\[0-9\]\* heads=/refs=[1-9] heads=/'; then mutant_red g4-2-pattern-narrowed-to-one-digit case_two_digit "$MUT"; fi
case_junk_refused() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m7 "X$GOOD" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ]; }
if mutate_cutover g4-no-caret "s/pat='\^refs_assert/pat='refs_assert/"; then mutant_red g4-3-pattern-start-anchor-dropped case_junk_refused "$MUT"; fi
case_41hex_refused() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m8 "refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=${C1}0" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ]; }
if mutate_cutover g4-hex-open 's/shas=\[0-9a-f\]\{40\}\(/shas=[0-9a-f]{40,}(/'; then mutant_red g4-4-sha-length-open-ended case_41hex_refused "$MUT"; fi
case_tail_refused() { local c="$CUTOVER"; CUTOVER="$1"; run_verb m9 "$GOOD extra" 0; local r="$VRC"; CUTOVER="$c"; [ "$r" = 5 ]; }
if mutate_cutover g4-no-dollar "s/\)\{0,1\}\\$'/){0,1}'/"; then mutant_red g4-5-pattern-end-anchor-dropped case_tail_refused "$MUT"; fi
SCAN_ON=1

echo "--- print scan over the tier-B runs"
if [ "${#SCAN_FAILS[@]}" = 0 ] && [ "$VERB_SCAN_RUNS" -ge 40 ]; then ok "SCAN-B no fixture identifier or stray sha reached the log, summary or output in any of $VERB_SCAN_RUNS verb runs"; else no "SCAN-B leaks or too few runs ($VERB_SCAN_RUNS): ${SCAN_FAILS[*]}"; fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# Workflow notify body (AC10): the extracted body run with a poisoned environment
# ══════════════════════════════════════════════════════════════════════════════════════════
echo "--- notify-failure body (AC10)"
python3 - "$WF" "$T/notify-body.sh" > "$T/nb.out" 2> "$T/nb.err" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["notify-failure"]["steps"]
body = next(s for s in steps if s.get("id") == "body")
open(sys.argv[2], "w").write(body["run"])
PY
if [ -s "$T/notify-body.sh" ]; then
  run_notify() { # <class> -> sets NOUT (GITHUB_OUTPUT) and NTXT (notify-body.txt)
    local d="$T/nb-$1"; rm -rf "$d"; mkdir -p "$d"
    : > "$d/out"; : > "$d/summary"
    env -i PATH=/usr/bin:/bin RUNNER_TEMP="$d" GITHUB_OUTPUT="$d/out" GITHUB_STEP_SUMMARY="$d/summary" \
      MODE=refs_assert RESULT=failure CUTOVER_RESULT=failure REFS_CLASS="$2" RUN_ID=123456 RUN_URL=https://example.invalid/run/123456 \
      FINALIZER_RAN=1 POISON_SHA="$C1" POISON_ID="$WT_A" bash "$T/notify-body.sh" > "$d/stdout" 2> "$d/stderr" || return 1
    NOUT="$(cat "$d/out")"; NTXT="$(cat "$d/notify-body.txt")"
  }
  NOUT=""; NTXT=""
  if run_notify f FAILED && grep -q '^subject=.*REFS_ASSERT_FAILED' <<< "$NOUT" && ! grep -q 'REFS_ASSERT_INCONCLUSIVE' <<< "$NOUT$NTXT" && grep -qF 'read-only: nothing on any host changed' <<< "$NTXT" \
     && ! grep -qF -e "$C1" -e "$WT_A" <<< "$NOUT$NTXT"; then ok "NB1 refs_class=FAILED -> REFS_ASSERT_FAILED, the read-only sentence, no sha and no id"; else no "NB1 FAILED notify: out=[$(head -c 300 <<< "$NOUT")]"; fi
  if run_notify i INCONCLUSIVE && grep -q '^subject=.*REFS_ASSERT_INCONCLUSIVE' <<< "$NOUT" && ! grep -q 'REFS_ASSERT_FAILED' <<< "$NOUT$NTXT" && grep -qF 'read-only: nothing on any host changed' <<< "$NTXT"; then ok "NB2 refs_class=INCONCLUSIVE -> REFS_ASSERT_INCONCLUSIVE"; else no "NB2 INCONCLUSIVE notify: out=[$(head -c 300 <<< "$NOUT")]"; fi
  if run_notify e ""  && grep -q '^subject=.*REFS_ASSERT_INCONCLUSIVE' <<< "$NOUT"; then ok "NB3 an absent refs_class (a runner-side refusal before the verb) reads INCONCLUSIVE, never FAILED"; else no "NB3 empty class: out=[$(head -c 300 <<< "$NOUT")]"; fi
  if run_notify x "FAILED; echo pwn" && grep -q '^subject=.*REFS_ASSERT_INCONCLUSIVE' <<< "$NOUT"; then ok "NB4 a refs_class outside the closed set is INCONCLUSIVE (the value is never interpolated)"; else no "NB4 hostile class: out=[$(head -c 300 <<< "$NOUT")]"; fi
else no "NB0 the notify body could not be extracted from the workflow: $(head -c 200 "$T/nb.err")"; fi
_c="$(grep -c -e REFS_ASSERT_INCONCLUSIVE "$WF" || true)"; _d="$(grep -c -e REFS_ASSERT_FAILED "$WF" || true)"
if [ "$_c" = 2 ] && [ "$_d" = 2 ]; then ok "NB5 each notify word appears on exactly two lines of the workflow (the words= line and the swords= line; no comment names it)"; else no "NB5 notify word line counts: INCONCLUSIVE=$_c FAILED=$_d"; fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# Runbook parity (script exit-code table <-> Verdict map)
# ══════════════════════════════════════════════════════════════════════════════════════════
echo "--- runbook parity"
rbp_py() { python3 - "$1" "$2" <<'PY'
import re, sys
script = open(sys.argv[1]).read()
rb = open(sys.argv[2]).read()
hdr = script.split("# EXIT CODES", 1)[1].split("\n# Inputs", 1)[0]
rows = re.findall(r"^#\s+([0-9]+)\s+([a-z_]+)\s+(REFS-CONFIRMED|FAILED|INCONCLUSIVE)\b", hdr, re.M)
words = {b: c for a, b, c in rows if a not in ("0", "16")}
vm = rb.split("\n## Verdict map", 1)[1].split("\n## ", 1)[0]
vrows = [l for l in vm.splitlines() if l.startswith("|")]
bad = []
for w, c in sorted(words.items()):
    hits = [l for l in vrows if "`%s`" % w in l]
    if len(hits) != 1: bad.append("%s:rows=%d" % (w, len(hits))); continue
    first = hits[0].split("|")[1]
    if c not in first: bad.append("%s:class-not-%s" % (w, c))
    if "REFS-CONFIRMED" in first: bad.append("%s:wrong-class" % w)
print("WORDS", sorted(words))
print("BAD", bad)
print("OK", not bad and len(words) == 7)
sec = rb.split("### Reading REFS-CONFIRMED", 1)
print("SECTION", len(sec) == 2)
body = sec[1].split("\n### ", 1)[0].split("\n## ", 1)[0] if len(sec) == 2 else ""
print("NOSSH", not re.search(r"\b(ssh|docker exec|journalctl|systemctl)\b", body + "\n".join(l for l in vrows if "refs_" in l)))
print("STALE", len(re.findall(r"follow-up, not yet built|refs_assert not built|refs_assert. is not built", rb)))
# the retryability column (the header's "(retryable)" / "(not retryable)") against the runbook's retry rule
hl = [l for l in hdr.splitlines() if re.match(r"^#\s+[0-9]+\s+[a-z_]+\s+(FAILED|INCONCLUSIVE)\b", l)]
retry = sorted(re.match(r"^#\s+[0-9]+\s+([a-z_]+)", l).group(1) for l in hl if "(retryable)" in l and "(not retryable)" not in l)
noretry = sorted(re.match(r"^#\s+[0-9]+\s+([a-z_]+)", l).group(1) for l in hl if "(not retryable)" in l)
m = re.search(r"Only `([a-z_]+)` and `([a-z_]+)` may be re-dispatched", rb)
rb_retry = sorted(m.groups()) if m else []
nr = rb.split("NOT retryable", 1)[1][:900] if "NOT retryable" in rb else ""
print("RETRY", retry, rb_retry, retry == rb_retry and len(retry) == 2)
print("NORETRY", noretry, all("`%s`" % w in nr for w in noretry) and len(noretry) == 2)
PY
}
rbp_py "$SCRIPT" "$RUNBOOK" > "$T/rb.out" 2> "$T/rb.err"
if grep -q '^OK True$' "$T/rb.out"; then ok "RBP1 each of the seven refs words has exactly one Verdict-map row, its first cell carries the script header's class"; else no "RBP1 runbook parity: $(tr '\n' ' ' < "$T/rb.out" | cut -c1-300) $(head -c 200 "$T/rb.err")"; fi
if grep -q '^SECTION True$' "$T/rb.out" && grep -q '^NOSSH True$' "$T/rb.out" && grep -q '^STALE 0$' "$T/rb.out"; then ok "RBP2 the runbook has '### Reading REFS-CONFIRMED', no SSH wording in it or in the refs Verdict rows, and no 'not yet built' wording"; else no "RBP2 runbook section: $(tr '\n' ' ' < "$T/rb.out" | cut -c1-300)"; fi

if grep -q '^RETRY .* True$' "$T/rb.out" && grep -q '^NORETRY .* True$' "$T/rb.out"; then ok "RBP3 the header's retryability column equals the runbook's retry rule: the retryable words (probe_failed, refs_unreadable) are the only re-dispatchable ones, and every not-retryable word is named in its NOT retryable sentence"; else no "RBP3 retryability parity: $(grep -E '^(RETRY|NORETRY)' "$T/rb.out" | tr '\n' ' ')"; fi
# mutation: the runbook's retry sentence drops a word / the header marks another word retryable -> RBP3 must go RED
cp "$RUNBOOK" "$T/mut/rb-retry.md"; sed -i 's/Only `probe_failed` and `refs_unreadable` may be re-dispatched/Only `probe_failed` and `refs_shape_failed` may be re-dispatched/' "$T/mut/rb-retry.md"
cp "$SCRIPT" "$T/mut/hdr-retry.sh"; sed -i 's/^#   26  refs_unreadable       INCONCLUSIVE     \(.*\) (retryable)$/#   26  refs_unreadable       INCONCLUSIVE     \1 (not retryable)/' "$T/mut/hdr-retry.sh"
MUTANTS_RUN=$((MUTANTS_RUN + 2))
if cmp -s "$RUNBOOK" "$T/mut/rb-retry.md" || cmp -s "$SCRIPT" "$T/mut/hdr-retry.sh"; then no "mutation rbp3: an edit did not land"; else
  rbp_py "$SCRIPT" "$T/mut/rb-retry.md" 2>/dev/null | grep -q '^RETRY .* True$' && no "mutant rbp3-runbook-retry-word: stayed GREEN" || ok "mutant rbp3-runbook-retry-word: goes RED (the runbook retry sentence changed and the parity caught it)"
  rbp_py "$T/mut/hdr-retry.sh" "$RUNBOOK" 2>/dev/null | grep -q '^RETRY .* True$' && no "mutant rbp3-header-retry-column: stayed GREEN" || ok "mutant rbp3-header-retry-column: goes RED (the header column changed and the parity caught it)"
fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# Floors (ADR-193: reported with printf + exit, never through ok()/no())
# ══════════════════════════════════════════════════════════════════════════════════════════
MIN_ASSERTIONS=265
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s -- rows were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
MUTANT_FLOOR=80
if [ "$MUTANTS_RUN" -ne "$MUTANT_FLOOR" ]; then
  printf '[FATAL] mutant floor: %s mutants ran, the floor is exactly %s -- a mutation row did not land, was deleted, or was added without restating the floor\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
SCAN_FLOOR_A=92
SCAN_FLOOR_B=56
if [ "$TIERA_SCAN_RUNS" -lt "$SCAN_FLOOR_A" ] || [ "$VERB_SCAN_RUNS" -lt "$SCAN_FLOOR_B" ]; then
  printf '[FATAL] print-scan floor: %s tier-A runs (floor %s) and %s verb runs (floor %s) were scanned\n' "$TIERA_SCAN_RUNS" "$SCAN_FLOOR_A" "$VERB_SCAN_RUNS" "$SCAN_FLOOR_B" >&2
  exit 1
fi
printf 'floor: %s assertions (floor %s), %s mutants (floor %s), %s tier-A and %s verb print-scan runs\n' "$executed" "$MIN_ASSERTIONS" "$MUTANTS_RUN" "$MUTANT_FLOOR" "$TIERA_SCAN_RUNS" "$VERB_SCAN_RUNS"
echo "=== git-data-refs-assert.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
