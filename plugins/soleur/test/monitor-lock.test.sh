#!/usr/bin/env bash
# Suite for the per-PR monitor lock (P4c of #10924): plugins/soleur/scripts/lib/monitor-lock.sh and its wiring in
# plugins/soleur/scripts/monitor-pr-checks.sh. Kept apart from monitor-pr-checks.test.sh, which sleeps at the 10 s
# interval floor (245 s in CI); every arm here finishes in well under a minute.
#
# `gh` and `git` are stubbed on PATH, `ps` is wrapped only where a zombie / missing-ps shape is needed. No network,
# no credentials, no pkill / pgrep -f: the only signalled pids are ones this suite started or parsed from a link in
# its own scratch lock directory.
#
# The mutation section copies the two files into a scratch tree, edits one marked line with sed, and counts a mutant
# KILLED only when its targeted check returns exactly 1 = "the guard failed". A check returns 2 when its OWN setup
# failed (a holder never took the lock, a script never started): that is reported as a harness failure, never a kill.
# The mutant must also still pass `bash -n`.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$DIR/soleur/scripts/monitor-pr-checks.sh"
LIB="$DIR/soleur/scripts/lib/monitor-lock.sh"
[[ -x "$SUT" && -r "$LIB" ]] || { printf 'FATAL: SUT or lib missing (%s, %s)\n' "$SUT" "$LIB" >&2; exit 1; }
REAL_GIT="$(command -v git)"

pass_n=0; fail_n=0
ok()  { pass_n=$((pass_n+1)); printf '  [ok] %s\n' "$1"; }
no()  { fail_n=$((fail_n+1)); printf '  [FAIL] %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '        %s\n' "$2" >&2; return 0; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once, then roll back.
_p=$pass_n _f=$fail_n; ok "selftest"; no "selftest" >/dev/null 2>&1
if [[ "$pass_n" -eq $((_p+1)) && "$fail_n" -eq $((_f+1)) ]]; then
  pass_n=$_p; fail_n=$_f; ok "INSTRUMENT: ok() and fail() each move their own counter"
else
  printf '  [FAIL] INSTRUMENT: ok()/no() do not each move their own counter — every assertion below is decorative\n' >&2
  exit 1
fi
skip_n=0
skip() { skip_n=$((skip_n+1)); printf '  [skip] %s\n' "$1"; }

HOLDERS=()
STUB="$(mktemp -d)"
cleanup() {
  local h
  for h in "${HOLDERS[@]:-}"; do [[ -n "$h" ]] && kill "$h" 2>/dev/null; done
  chmod -R u+rwx "$STUB" 2>/dev/null
  rm -rf "$STUB"
}
trap cleanup EXIT
case "$STUB" in /?*) : ;; *) printf 'FATAL: non-absolute scratch dir %s\n' "$STUB" >&2; exit 1 ;; esac
mkdir -p "$STUB/bin" "$STUB/psbin" "$STUB/nogit" "$STUB/tree/lib" || { echo "FATAL: scratch setup failed" >&2; exit 1; }

# gh: logs every argv; view/checks answer from env so one stub serves every arm (pending checks -> the watch times out).
cat > "$STUB/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GHLOG:?}"
case "$1 $2" in
  "pr view")   printf '%s' "${GH_VIEW:-OPEN|BLOCKED|true}" ;;
  "pr checks") printf '%s' '[{"name":"a","bucket":"pass"},{"name":"test-scripts","bucket":"pending"}]' ;;
esac
EOF
# git: answers exactly `config --get remote.origin.url` (raw, STUB_ORIGIN) and `remote get-url origin` (alias-resolved,
# STUB_ORIGIN_URL, else STUB_ORIGIN); everything else is the real git.
cat > "$STUB/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "config --get remote.origin.url" ]]; then
  printf '%s\n' "\${STUB_ORIGIN:-}"; [[ -n "\${STUB_ORIGIN:-}" ]]; exit \$?
fi
if [[ "\$*" == "remote get-url origin" ]]; then
  u="\${STUB_ORIGIN_URL:-\${STUB_ORIGIN:-}}"; printf '%s\n' "\$u"; [[ -n "\$u" ]]; exit \$?
fi
exec "$REAL_GIT" "\$@"
EOF
# ps wrapper: refuses (exit 64) any argv other than the one shape the lib is specified to send, so dropping or
# reordering a selector reds a test instead of being answered anyway. PS_ZOMBIE_PID rewrites that pid's state column
# to PS_ZOMBIE_STAT (default Z); PS_BROKEN=1 behaves like an absent ps.
REAL_PS="$(command -v ps)"
cat > "$STUB/psbin/ps" <<EOF
#!/usr/bin/env bash
[[ "\${PS_BROKEN:-}" == 1 ]] && exit 127
if [[ "\$#" -ne 8 || "\$1 \$2 \$3 \$4 \$5 \$6 \$7" != "-o pid= -o stat= -o lstart= -p" ]]; then
  echo "ps stub: unexpected argv: \$*" >&2; exit 64
fi
out="\$("$REAL_PS" "\$@")" || exit \$?
last=""; for a in "\$@"; do last="\$a"; done
if [[ -n "\${PS_ZOMBIE_PID:-}" && "\$last" == "\$PS_ZOMBIE_PID" ]]; then
  printf '%s\n' "\$out" | awk -v z="\${PS_ZOMBIE_STAT:-Z}" '{ \$2 = z; print }'
else
  printf '%s\n' "\$out"
fi
EOF
chmod +x "$STUB/bin/gh" "$STUB/bin/git" "$STUB/psbin/ps"
export GHLOG="$STUB/gh.log"; : > "$GHLOG"
export SOLEUR_MONITOR_LOCK_GRACE_S=0
unset SOLEUR_MONITOR_LOCK XDG_RUNTIME_DIR 2>/dev/null || true

# newdir is called through $(...), a subshell: a counter would not survive it, so every call would share one directory.
newdir() { mktemp -d "$STUB/ld.XXXXXX"; }

wait_link() {  # wait_link <path> [tenths] — wait for the lock link to appear
  local i=0 max="${2:-100}"
  while [[ ! -L "$1" && "$i" -lt "$max" ]]; do sleep 0.1; i=$((i+1)); done
  [[ -L "$1" ]]
}
wait_gone() {  # wait_gone <path> <tenths>
  local i=0
  while [[ -L "$1" && "$i" -lt "$2" ]]; do sleep 0.1; i=$((i+1)); done
  [[ ! -L "$1" ]]
}
# hold <libdir> <lockdir> <repo> <pr> [env...] — a background process that holds the lock via the given lib; sets HP.
hold() {
  local lib="$1" ld="$2" repo="$3" pr="$4"; shift 4
  env SOLEUR_MONITOR_LOCK_DIR="$ld" "$@" bash -c '. "$1" && monitor_lock_acquire "$2" "$3" && exec sleep 300' _ "$lib/monitor-lock.sh" "$repo" "$pr" &
  HP=$!; HOLDERS+=("$HP")
  # Wait for ANY lock link, not one derived name: a mutant that renames the key must reach its own assertion rather
  # than time out here and be miscounted as a kill.
  local i=0
  while [[ "$i" -lt 100 ]] && [[ -z "$(find "$ld" -maxdepth 1 -name '*.lock' -type l 2>/dev/null)" ]]; do sleep 0.1; i=$((i+1)); done
  [[ -n "$(find "$ld" -maxdepth 1 -name '*.lock' -type l 2>/dev/null)" ]]
}
lockname() { printf 'pr-checks+%s+%s.lock' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '/' '+')" "$2"; }
unhold() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; return 0; }
# lib_call <lockdir> <script...> — run a snippet with the real lib sourced in a fresh bash; prints its stdout.
lib_call() {
  local ld="$1" code="$2"; shift 2
  SOLEUR_MONITOR_LOCK_DIR="$ld" bash -c 'set -u; . "$1"; code="$2"; shift 2; eval "$code"' _ "$LIB" "$code" "$@"
}
# run_tree <treedir> <lockdir> <args...> — run the monitor script from a tree (gh/git/ps stubs on PATH).
run_tree() {
  local tree="$1" ld="$2"; shift 2
  ( cd "$STUB/nogit" && env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$ld" GIT_CEILING_DIRECTORIES="$STUB" \
      timeout 60 bash "$tree/monitor-pr-checks.sh" "$@" )
}
# a pristine tree for the real code under test: the script + its lib (so a copy sources its own lib)
cp "$SUT" "$STUB/tree/monitor-pr-checks.sh"; cp "$LIB" "$STUB/tree/lib/monitor-lock.sh"
REAL_TREE="$(dirname "$SUT")"   # the in-repo directory: script + lib/
IS_ROOT=0; [[ "$(id -u)" == 0 ]] && IS_ROOT=1

# ── The refusal line, exactly ─────────────────────────────────────────────────────
expect_line() {  # expect_line <pr> <pid> <age> <repo>
  printf 'DUPLICATE MONITOR — PR #%s is already watched by pid %s (watching for %ss, repo %s). This watch exits without polling. Only if this session still has a running Monitor task for that PR, read that task'"'"'s output. Otherwise it belongs to a resumed or other session (or one you already stopped): check that "ps -o args= -p %s" names monitor-pr-checks.sh, then stop it with: kill %s — and arm this watch once.' "$1" "$2" "$3" "$4" "$2" "$2"
}

# ── Checks shared by the real-tree arms and the mutation battery. Each returns 0 when the guard HOLDS, 1 when it
#    does not, 2 when its own SETUP failed; none crashes the suite. $1 = tree dir (script + lib/). ─────────────────
chk_refuse() {   # a second monitor on a held (repo, PR) is refused: rc exactly 4, the exact line, and ZERO gh calls
  local t="$1" ld out rc=0 age
  ld="$(newdir)"; hold "$t/lib" "$ld" acme/widgets 7 || { unhold "$HP"; return 2; }
  : > "$GHLOG"
  out="$(run_tree "$t" "$ld" 7 --repo acme/widgets --interval 10 --max-polls 1 2>&1)" || rc=$?
  unhold "$HP"
  age="$(sed -n 's/.*watching for \([0-9][0-9]*\)s,.*/\1/p' <<<"$out")"
  [[ "$rc" -eq 4 && -n "$age" && "$out" == "$(expect_line 7 "$HP" "$age" acme/widgets)" && ! -s "$GHLOG" ]]
}
chk_keys_pr() {  # PR 1 held: PR 2 must run (not refused); PR 1 again must be refused
  local t="$1" ld rc2=0 rc1=0
  ld="$(newdir)"; hold "$t/lib" "$ld" acme/widgets 1 || { unhold "$HP"; return 2; }
  run_tree "$t" "$ld" 2 --repo acme/widgets --interval 10 --max-polls 1 >/dev/null 2>&1 || rc2=$?
  run_tree "$t" "$ld" 1 --repo acme/widgets --interval 10 --max-polls 1 >/dev/null 2>&1 || rc1=$?
  unhold "$HP"
  [[ "$rc2" -ne 4 && "$rc1" -eq 4 ]]
}
chk_keys_repo() {  # same PR number in another repo must not conflict
  local t="$1" ld rc=0
  ld="$(newdir)"; hold "$t/lib" "$ld" a/x 1 || { unhold "$HP"; return 2; }
  run_tree "$t" "$ld" 1 --repo b/y --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
  unhold "$HP"
  [[ "$rc" -ne 4 ]]
}
chk_lstart() {  # a LIVE pid recorded with a wrong start time is stale: reclaimed, not refused
  local t="$1" ld sleeper rc=0
  ld="$(newdir)"; sleep 300 & sleeper=$!; HOLDERS+=("$sleeper")
  ln -s "$sleeper|Mon_Jan__1_00:00:00_2001|1" "$ld/pr-checks+acme+widgets+3.lock"
  SOLEUR_MONITOR_LOCK_DIR="$ld" bash -c '. "$1" && monitor_lock_acquire acme/widgets 3' _ "$t/lib/monitor-lock.sh" >/dev/null 2>&1 || rc=$?
  unhold "$sleeper"
  [[ "$rc" -eq 0 ]]
}
chk_zombie() {  # a holder whose state is Z / Z+ / Zs is stale even though ps lists it and its start time matches
  local t="$1" ld rc st
  for st in Z Z+ Zs; do
    rc=0
    ld="$(newdir)"; hold "$t/lib" "$ld" acme/widgets 4 || { unhold "$HP"; return 2; }
    PS_ZOMBIE_STAT="$st" PS_ZOMBIE_PID="$HP" PATH="$STUB/psbin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$ld" \
      bash -c '. "$1" && monitor_lock_acquire acme/widgets 4' _ "$t/lib/monitor-lock.sh" >/dev/null 2>&1 || rc=$?
    unhold "$HP"
    [[ "$rc" -eq 0 ]] || return 1
  done
  return 0
}
chk_tz() {  # a holder recorded under TZ=UTC is still refused when read under another TZ
  local t="$1" ld rc=0
  ld="$(newdir)"; hold "$t/lib" "$ld" acme/widgets 5 TZ=UTC || { unhold "$HP"; return 2; }
  TZ=Asia/Tokyo SOLEUR_MONITOR_LOCK_GRACE_S=0 SOLEUR_MONITOR_LOCK_DIR="$ld" \
    bash -c '. "$1" && monitor_lock_acquire acme/widgets 5' _ "$t/lib/monitor-lock.sh" >/dev/null 2>&1 || rc=$?
  unhold "$HP"
  [[ "$rc" -eq 1 ]]
}
chk_release() {  # release never removes a link that names someone else
  local t="$1" ld out
  ld="$(newdir)"
  out="$(SOLEUR_MONITOR_LOCK_DIR="$ld" bash -c '. "$1"; monitor_lock_acquire acme/widgets 6 || exit 9
    l="$SOLEUR_MONITOR_LOCK_DIR/pr-checks+acme+widgets+6.lock"; rm -f "$l"; ln -s "424242|x|1" "$l"
    monitor_lock_release; [ -L "$l" ] && echo SURVIVED' _ "$t/lib/monitor-lock.sh" 2>&1)"
  [[ "$out" == "SURVIVED" ]]
}
chk_cleanup() {  # a normal terminal exit leaves no link behind
  local t="$1" ld rc=0
  ld="$(newdir)"
  GH_VIEW='MERGED|CLEAN|false' run_tree "$t" "$ld" 7 --repo acme/widgets --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 && -z "$(ls -A "$ld")" ]]
}
chk_term() {  # TERM sent mid-sleep releases within 4 s (a TERM trap would hold it for the rest of the 10 s sleep)
  local t="$1" ld pid link released=1 wrc=0
  ld="$(newdir)"; link="$ld/$(lockname acme/widgets 8)"
  ( cd "$STUB/nogit" && exec env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$ld" bash "$t/monitor-pr-checks.sh" 8 --repo acme/widgets --interval 10 --max-polls 3 >/dev/null 2>&1 ) &
  pid=$!; HOLDERS+=("$pid")
  wait_link "$link" 100 || { kill "$pid" 2>/dev/null; return 2; }
  sleep 1   # the script is now inside its foreground `sleep`
  kill -0 "$pid" 2>/dev/null || return 2   # it must still be running when TERM lands, or the arm proves nothing
  kill -TERM "$pid" 2>/dev/null
  wait_gone "$link" 40 || released=0
  kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || wrc=$?
  rm -f "$link"
  [[ "$released" -eq 1 && "$wrc" -eq 143 ]]
}

# ── Unit arms (the lib, sourced in a fresh bash per call) ─────────────────────────
L="$(newdir)"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 7; echo "rc=$? pid=$$ state=$ML_STATE"; readlink "$SOLEUR_MONITOR_LOCK_DIR"/*.lock' 2>&1)"
pid_u="$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' <<<"$out")"
if [[ "$out" == *"rc=0"* && "$out" == *"state=held"* ]] && [[ -L "$L/pr-checks+acme+widgets+7.lock" ]] \
   && [[ "$(readlink "$L/pr-checks+acme+widgets+7.lock")" =~ ^${pid_u}\|[A-Za-z0-9_:]+\|[0-9]+$ ]]; then
  ok "U1 acquire on an empty dir: rc 0, link pr-checks+acme+widgets+7.lock, target <pid>|<lstart>|<epoch> with the caller's pid"
else no "U1 acquire" "out=[$out] link=$(readlink "$L/pr-checks+acme+widgets+7.lock" 2>&1)"; fi

L="$(newdir)"; hold "$REAL_TREE/lib" "$L" acme/widgets 7 >/dev/null 2>&1; HU=$HP
hold_ok=0; [[ -L "$L/pr-checks+acme+widgets+7.lock" ]] && hold_ok=1
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE hp=$ML_HOLDER_PID age=$ML_HOLDER_AGE"' 2>&1)"
[[ "$hold_ok" == 1 && "$out" == "rc=1 state=held-by-other hp=$HU age="[0-9]* ]] && ok "U2a a live other holder: rc 1, ML_HOLDER_PID and an ML_HOLDER_AGE" || no "U2a live holder" "out=[$out]"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 8; echo "pr=$?"; monitor_lock_acquire other/repo 7; echo "repo=$?"' 2>&1)"
[[ "$out" == $'pr=0\nrepo=0' ]] && ok "U2b a different PR and a different repo do not conflict" || no "U2b independent keys" "out=[$out]"
out="$(lib_call "$L" 'monitor_lock_acquire ACME/Widgets 7; echo "case=$?"; monitor_lock_acquire git@github.com:Acme/Widgets.git 7; echo "scp=$?"' 2>&1)"
[[ "$out" == $'case=1\nscp=1' ]] && ok "U2c ACME/Widgets and an scp-style origin map to the same key as acme/widgets (both refused)" || no "U2c case-fold / origin" "out=[$out]"
unhold "$HU"

# stale holders: dead pid, live pid + wrong lstart, zombie, malformed value, regular-file stand-in
L="$(newdir)"; sleep 0 & dead=$!; wait "$dead"
ln -s "$dead|Tue_Oct_27_00:00:00_2026|1" "$L/pr-checks+acme+widgets+10.lock"
ln -s "garbage" "$L/pr-checks+acme+widgets+11.lock"
: > "$L/pr-checks+acme+widgets+12.lock"
out="$(lib_call "$L" 'for p in 10 11 12; do monitor_lock_acquire acme/widgets $p; echo -n "$? "; done' 2>&1)"
[[ "$out" == "0 0 0 " ]] && ok "U3a a dead pid, a malformed value and a regular-file stand-in are reclaimed (rc 0)" || no "U3a stale reclaim" "out=[$out]"
chk_lstart "$REAL_TREE" && ok "U3b a LIVE pid with a wrong start time (pid reuse) is reclaimed, not refused" || no "U3b lstart mismatch"
chk_zombie "$REAL_TREE" && ok "U3c a zombie holder (state Z, Z+ and Zs) is reclaimed even though ps lists it and its start time matches" || no "U3c zombie"
L="$(newdir)"; mkdir "$L/pr-checks+acme+widgets+13.lock"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 13; echo "rc=$? state=$ML_STATE"' 2>&1)"
[[ "$out" == "rc=2 state=unavailable" && -d "$L/pr-checks+acme+widgets+13.lock" ]] && ok "U3d a directory at the lock path: rc 2 unavailable, left untouched" || no "U3d directory at path" "out=[$out]"
L="$(newdir)"; ln -s "424242|x|1" "$L/pr-checks+acme+widgets+14.lock"; mkdir -p "$STUB/noop"; printf '#!/bin/sh\nexit 0\n' > "$STUB/noop/rm"; chmod +x "$STUB/noop/rm"
out="$(PATH="$STUB/noop:$PATH" lib_call "$L" 'monitor_lock_acquire acme/widgets 14; echo "rc=$? state=$ML_STATE"' 2>&1)"
[[ "$out" == "rc=2 state=unavailable" ]] && ok "U3e a stale record that cannot be reclaimed is rc 2 contended, never a refusal" || no "U3e reclaim lost" "out=[$out]"
# a lock name that is a symlink to an existing directory: ln -n must not create the link INSIDE it
L="$(newdir)"; mkdir "$STUB/tgt"; ln -s "$STUB/tgt" "$L/$(lockname acme/widgets 23)"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 23; echo "rc=$?"; readlink "$SOLEUR_MONITOR_LOCK_DIR"/*.lock' 2>&1)"
[[ "$out" == "rc=0"$'\n'*"|"* && -z "$(ls -A "$STUB/tgt")" ]] && ok "U3f a lock name that is a symlink to a directory is replaced, and nothing is created inside the directory" || no "U3f symlink-to-dir" "out=[$out] inside=[$(ls -A "$STUB/tgt")]"
# a LIVE pid recorded with an EMPTY start time cannot prove it was not reused: stale
L="$(newdir)"; sleep 300 & sl=$!; HOLDERS+=("$sl"); ln -s "$sl||1" "$L/$(lockname acme/widgets 22)"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 22; echo "rc=$?"' 2>&1)"; unhold "$sl"
[[ "$out" == "rc=0" ]] && ok "U3g a live pid with no recorded start time is stale (reclaimed), never a refusal" || no "U3g empty lstart" "out=[$out]"
# a record naming OUR pid with a FOREIGN start time (a killed predecessor, another PID namespace) must be rewritten,
# or the next monitor reads this live holder as pid-reused and steals the lock
L="$(newdir)"
out="$(lib_call "$L" 'ln -s "$$|Mon_Jan__1_00:00:00_2001|1000000000" "$SOLEUR_MONITOR_LOCK_DIR/pr-checks+acme+widgets+9.lock"; monitor_lock_acquire acme/widgets 9; echo "rc=$?"; readlink "$SOLEUR_MONITOR_LOCK_DIR/pr-checks+acme+widgets+9.lock"' 2>&1)"
[[ "$out" == "rc=0"$'\n'*"|"* && "$out" != *Mon_Jan__1_00* ]] && ok "U3h a record naming our pid but a foreign start time is rewritten, not adopted" || no "U3h same-pid foreign lstart" "out=[$out]"

L="$(newdir)"
out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 7; a=$?; monitor_lock_acquire acme/widgets 7; echo "$a $?"' 2>&1)"
[[ "$out" == "0 0" ]] && ok "U4 re-acquiring a key this process already holds is an idempotent rc 0" || no "U4 idempotent" "out=[$out]"

L="$(newdir)"
out="$(lib_call "$L" 'monitor_lock_release; echo -n "none=$? "; monitor_lock_acquire acme/widgets 7; monitor_lock_release; [ -L "$SOLEUR_MONITOR_LOCK_DIR/pr-checks+acme+widgets+7.lock" ] && echo -n "LEFT " || echo -n "gone "; monitor_lock_release; echo "twice=$?"' 2>&1)"
[[ "$out" == "none=0 gone twice=0" ]] && ok "U5a release: nothing acquired is a no-op, own link removed, a second release is a no-op" || no "U5a release" "out=[$out]"
chk_release "$REAL_TREE" && ok "U5b release never deletes a link that names another process" || no "U5b release ownership"

L="$(newdir)"; mkdir "$STUB/realdir"; ln -s "$STUB/realdir" "$STUB/dirlink"; : > "$STUB/afile"
for d in "$STUB/dirlink" "$STUB/afile"; do
  out="$(SOLEUR_MONITOR_LOCK_DIR="$d" bash -c '. "$1"; monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE why=$ML_WHY"' _ "$LIB" 2>&1)"
  [[ "$out" == "rc=2 state=unavailable why="?* ]] && ok "U6 lock dir $(basename "$d") (symlink / regular file): rc 2 unavailable with a reason" || no "U6 bad lock dir $d" "out=[$out]"
done
if [[ "$IS_ROOT" == 0 ]]; then
  mkdir "$STUB/rodir"; chmod 500 "$STUB/rodir"
  out="$(SOLEUR_MONITOR_LOCK_DIR="$STUB/rodir" bash -c '. "$1"; monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE"' _ "$LIB" 2>&1)"
  [[ "$out" == "rc=2 state=unavailable" ]] && ok "U6 a read-only lock dir: rc 2 unavailable" || no "U6 read-only dir" "out=[$out]"
else skip "U6 read-only dir (running as root: -w succeeds on a chmod 500 dir; not counted)"; fi
out="$(SOLEUR_MONITOR_LOCK=off lib_call "$(newdir)" 'monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE"' 2>&1)"
[[ "$out" == "rc=2 state=disabled" ]] && ok "U6 SOLEUR_MONITOR_LOCK=off: rc 2 disabled" || no "U6 off switch" "out=[$out]"
mkdir "$STUB/open" && chmod 777 "$STUB/open"
out="$(SOLEUR_MONITOR_LOCK_DIR="$STUB/open" bash -c '. "$1"; monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE"' _ "$LIB" 2>&1)"
[[ "$out" == "rc=2 state=unavailable" ]] && ok "U6 a lock dir writable by group or other (mode 777) is refused" || no "U6 open lock dir" "out=[$out]"
out="$(SOLEUR_MONITOR_LOCK_DIR=/tmp bash -c '. "$1"; monitor_lock_acquire acme/widgets 7; echo "rc=$? state=$ML_STATE"' _ "$LIB" 2>&1)"
[[ "$out" == "rc=2 state=unavailable" ]] && ok "U6 /tmp itself (shared, not ours) is never used as the lock dir" || no "U6 /tmp as lock dir" "out=[$out]"
out="$(env -u SOLEUR_MONITOR_LOCK_DIR XDG_RUNTIME_DIR="$STUB/xdg" bash -c '. "$1"; monitor_lock_acquire acme/widgets 7; echo "rc=$?"' _ "$LIB" 2>&1)"
xd="$STUB/xdg/soleur-monitor-locks-$(id -u)"
[[ "$out" == "rc=0" && -L "$xd/pr-checks+acme+widgets+7.lock" && -n "$(find "$xd" -maxdepth 0 -perm 700 2>/dev/null)" ]] \
  && ok "U6 the default lock dir is \$XDG_RUNTIME_DIR/soleur-monitor-locks-<uid>, created mode 700" || no "U6 default lock dir" "out=[$out] ls=$(ls -ld "$xd" 2>&1)"

# repo spellings -> one key; credentials never reach a name; garbage fails open
forms=( 'acme/widgets' 'Acme/Widgets' 'git@github.com:Acme/Widgets.git' 'https://github.com/Acme/Widgets' 'https://github.com/Acme/Widgets.git/'
        'ssh://git@github.com/Acme/Widgets.git' 'https://x-access-token:SECRETTOKEN123@github.com/Acme/Widgets.git'
        'https://www.github.com/Acme/Widgets' 'ssh://git@github.com:22/Acme/Widgets.git' 'Acme/Widgets.GIT' 'github.com/Acme/Widgets' )
bad=""
for f in "${forms[@]}"; do
  v="$(bash -c '. "$1"; _ml_norm "$2"' _ "$LIB" "$f" 2>&1)"; [[ "$v" == "acme/widgets" ]] || bad="$bad [$f -> $v]"
done
[[ -z "$bad" ]] && ok "U7a ${#forms[@]} origin / --repo spellings normalise to acme/widgets" || no "U7a normaliser" "$bad"
L="$(newdir)"; lib_call "$L" 'monitor_lock_acquire "https://x-access-token:SECRETTOKEN123@github.com/Acme/Widgets.git" 7' >/dev/null 2>&1
names="$(ls -A "$L")"
[[ "$names" == "pr-checks+acme+widgets+7.lock" && "$names" != *SECRETTOKEN* ]] && ok "U7b a credential embedded in the origin URL never reaches the lock name" || no "U7b credential leak" "names=[$names]"
badg=""
for f in 'https://gitlab.com/a/b.git' '' 'not a url' 'github.com/a/b/c' 'ftp://github.com'; do
  out="$(lib_call "$(newdir)" 'monitor_lock_acquire "$1" 7; echo "$? $ML_STATE"' "$f" 2>&1)"; [[ "$out" == "2 unavailable" ]] || badg="$badg [$f -> $out]"
done
[[ -z "$badg" ]] && ok "U7c non-github hosts and garbage origins fail open (rc 2 unavailable), never refuse" || no "U7c garbage origins" "$badg"
out="$(lib_call "$(newdir)" 'monitor_lock_acquire acme/widgets abc; echo "$? $ML_STATE"' 2>&1)"
[[ "$out" == "2 unavailable" ]] && ok "U7d a non-numeric PR fails open (rc 2 unavailable), never reaches the lock name" || no "U7d non-numeric PR" "out=[$out]"
L="$(newdir)"; lib_call "$L" 'monitor_lock_acquire acme/widgets 007' >/dev/null 2>&1
[[ "$(ls -A "$L")" == "$(lockname acme/widgets 7)" ]] && ok "U7e a PR written 007 keys as 7 (leading zeros do not make a second lock)" || no "U7e leading-zero PR" "names=[$(ls -A "$L")]"
out="$(bash -c '. "$1"; _ml_norm "a+b/c"; echo "rc=$?"' _ "$LIB" 2>&1)"
[[ "$out" == "rc=1" ]] && ok "U8b a + in a repo name is rejected (it is the key separator)" || no "U8b plus in repo" "out=[$out]"
L="$(newdir)"; hold "$REAL_TREE/lib" "$L" 'a__b/c' 1 >/dev/null 2>&1; HU=$HP
out="$(lib_call "$L" 'monitor_lock_acquire a/b__c 1; echo "$?"' 2>&1)"; unhold "$HU"
[[ "$out" == "0" ]] && ok "U8 a__b/c and a/b__c do not collide (the + separator is outside the repo grammar)" || no "U8 name collision" "out=[$out]"
TZ_OK=1
if [[ "$(TZ=Asia/Tokyo date +%H)" != "$(TZ=UTC date +%H)" ]]; then
  chk_tz "$REAL_TREE" && ok "U9 a holder recorded under TZ=UTC is still refused when read under TZ=Asia/Tokyo" || no "U9 TZ pin"
else TZ_OK=0; skip "U9 TZ pin (no tz database here: TZ=Asia/Tokyo reads as UTC, the arm could not discriminate; not counted)"; fi
if [[ "$IS_ROOT" == 0 ]]; then
  L="$(newdir)"; ident1="$(bash -c '. "$1"; _ml_ident 1' _ "$LIB" 2>/dev/null)"
  if [[ -n "$ident1" ]]; then
    ln -s "1|${ident1#*|}|1" "$L/pr-checks+acme+widgets+20.lock"
    out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 20; echo "$? $ML_HOLDER_PID"' 2>&1)"
    [[ "$out" == "1 1" ]] && ok "U10 a live holder owned by another user (pid 1) stays refused (ps -p, not kill -0)" || no "U10 other-user holder" "out=[$out]"
  else skip "U10 (ps cannot read pid 1 here; not counted)"; fi
else skip "U10 other-user holder (running as root: kill -0 1 succeeds, the arm would prove nothing; not counted)"; fi

# a planted epoch with a leading zero (08, 09) is octal to $(( )): it must not abort the acquire call
ident1="$(bash -c '. "$1"; _ml_ident 1' _ "$LIB" 2>/dev/null)"
if [[ -n "$ident1" ]]; then
  L="$(newdir)"; ln -s "1|${ident1#*|}|08" "$L/$(lockname acme/widgets 21)"
  out="$(lib_call "$L" 'monitor_lock_acquire acme/widgets 21; echo "$? $ML_HOLDER_PID $ML_HOLDER_AGE"' 2>&1)"
  [[ "$out" =~ ^1\ 1\ [0-9]+$ ]] && ok "U10b a leading-zero epoch in a planted record is read as decimal (no octal abort, a real age)" || no "U10b octal epoch" "out=[$out]"
else skip "U10b (ps cannot read pid 1 here; not counted)"; fi

# F10: a live holder that RELEASES inside the grace window is acquired, not refused
L="$(newdir)"
( SOLEUR_MONITOR_LOCK_DIR="$L" bash -c '. "$1"; monitor_lock_acquire acme/widgets 31 || exit 9; sleep 1; monitor_lock_release' _ "$LIB" ) &
gp=$!; HOLDERS+=("$gp"); wait_link "$L/$(lockname acme/widgets 31)" 50
out="$(SOLEUR_MONITOR_LOCK_GRACE_S=2 lib_call "$L" 'monitor_lock_acquire acme/widgets 31; echo "rc=$?"' 2>&1)"; wait "$gp" 2>/dev/null
[[ "$out" == "rc=0" ]] && ok "U11 a holder that releases inside the grace window is acquired (the stop-then-re-arm path)" || no "U11 grace retry" "out=[$out]"

# several contenders against ONE stale record: exactly one may win (the reclaim must be serialised)
race_bad=0; race_log="$STUB/race.log"
sleep 0 & dead2=$!; wait "$dead2"
for _round in 1 2 3 4 5 6; do
  L="$(newdir)"; : > "$race_log"
  ln -s "$dead2|Tue_Oct_27_00:00:00_2026|1" "$L/$(lockname acme/widgets 30)"
  rpids=()
  for _k in 1 2 3 4 5 6; do
    SOLEUR_MONITOR_LOCK_DIR="$L" bash -c '. "$1" && monitor_lock_acquire acme/widgets 30 && { echo W >> "$2"; exec sleep 30; }' _ "$LIB" "$race_log" >/dev/null 2>&1 &
    rpids+=("$!")
  done
  sleep 0.7
  [[ "$(wc -l < "$race_log" | tr -d ' ')" == "1" ]] || race_bad=$((race_bad+1))
  for rp in "${rpids[@]}"; do kill "$rp" 2>/dev/null; done; wait 2>/dev/null
done
[[ "$race_bad" -eq 0 ]] && ok "U13 six contenders racing for one stale record: exactly one wins, in each of 6 rounds" || no "U13 stale-reclaim race" "$race_bad of 6 rounds had a number of winners other than one"

# ── Integration arms (the real script, stubbed gh/git) ────────────────────────────
chk_refuse "$REAL_TREE" && ok "I1 a second monitor on a held (repo, PR): rc exactly 4, the exact DUPLICATE MONITOR line, zero gh calls" || no "I1 refusal"

L="$(newdir)"; hold "$REAL_TREE/lib" "$L" acme/widgets 7 >/dev/null 2>&1; HI=$HP
line="$(run_tree "$REAL_TREE" "$L" 7 --repo acme/widgets --interval 10 --max-polls 1 2>&1)"; unhold "$HI"
nl="$(wc -l <<<"$line")"
tokens="$(grep -c -e MERGED -e GREEN -e CLOSED -e SETTLED -e TIMEOUT -e QUEUE -e KILLED -e UNMERGED <<<"$line")"
ctl="$(grep -c -e MERGED -e GREEN <<<"PR MERGED")"
if [[ "$nl" -eq 1 && "$tokens" == 0 && "$ctl" == 1 && "$line" == *"kill $HI"* && "$line" == *"ps -o args= -p $HI"* && "$line" != *SOLEUR_MONITOR_LOCK* ]]; then
  ok "I2 the refusal is one line with the holder pid, a check-then-kill instruction, no bypass hint, and none of the verdict tokens a caller could read as an outcome"
else no "I2 refusal wording" "lines=$nl tokens=$tokens line=[$line]"; fi

chk_keys_pr "$REAL_TREE" && ok "I3a PR 1 held: PR 2 runs, PR 1 again is refused (the key follows the PR number)" || no "I3a per-PR key"
chk_keys_repo "$REAL_TREE" && ok "I3b same PR number, different repo: not refused (the key follows the repo)" || no "I3b per-repo key"

chk_cleanup "$REAL_TREE" && ok "I4 a normal MERGED exit (rc 0) leaves no link behind" || no "I4 release on terminal exit"
L="$(newdir)"; rc=0; run_tree "$REAL_TREE" "$L" 7 --repo acme/widgets --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 && -z "$(ls -A "$L")" ]] && ok "I4b a TIMEOUT exit (rc 2) leaves no link behind" || no "I4b release on timeout" "rc=$rc left=$(ls -A "$L")"

L="$(newdir)"; link="$L/pr-checks+acme+widgets+8.lock"
( cd "$STUB/nogit" && exec env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$L" bash "$SUT" 8 --repo acme/widgets --interval 10 --max-polls 3 >/dev/null 2>&1 ) &
tp=$!; HOLDERS+=("$tp")
if wait_link "$link" 100; then
  chk=$(readlink "$link"); [[ "${chk%%|*}" == "$tp" ]] && ok "I5a the recorded pid is the script's own bash" || no "I5a recorded pid" "link=$chk tp=$tp"
  sleep 1; kill -TERM "$tp" 2>/dev/null
  wait_gone "$link" 40 && ok "I5b TERM sent mid-sleep releases the lock within 4 s (no TERM trap defers it)" || no "I5b TERM release" "link still present"
  rc=0; run_tree "$REAL_TREE" "$L" 8 --repo acme/widgets --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] && ok "I5c TERM then an immediate second monitor acquires and runs" || no "I5c re-arm after TERM" "rc=$rc"
else no "I5 monitor never took the lock"; fi
kill -KILL "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; rm -f "$link"

chk_term "$REAL_TREE" && ok "I5d chk_term (shared with mutation row 10) passes on the real tree" || no "I5d chk_term"

# fail-open arms: each runs the watch and says why; none exits 4
failopen() {  # failopen <label> <expect-substring> <env...> -- <args...>
  local label="$1" want="$2" ld out rc=0; shift 2
  ld="$(newdir)"
  local envs=(); while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  out="$(cd "$STUB/nogit" && env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$ld" GIT_CEILING_DIRECTORIES="$STUB" "${envs[@]+"${envs[@]}"}" \
        timeout 60 bash "$SUT" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -ne 4 && "$out" == *"$want"* && "$out" == *"pass ·"* ]]; then ok "I6 $label: prints its loud line and still polls"; else no "I6 $label" "rc=$rc out=[$out]"; fi
}
failopen "SOLEUR_MONITOR_LOCK=off" "monitor-lock: DISABLED (SOLEUR_MONITOR_LOCK=off) - running without exclusion" SOLEUR_MONITOR_LOCK=off -- 7 --repo acme/widgets --interval 10 --max-polls 1
failopen "no ps" "monitor-lock: UNAVAILABLE (ps cannot read this process start time) - running without exclusion" PATH="$STUB/psbin:$STUB/bin:$PATH" PS_BROKEN=1 -- 7 --repo acme/widgets --interval 10 --max-polls 1
failopen "no --repo and no origin" "monitor-lock: UNAVAILABLE (repo not derivable" -- 7 --interval 10 --max-polls 1
failopen "non-github origin" "monitor-lock: UNAVAILABLE (repo not derivable" STUB_ORIGIN=https://gitlab.com/a/b.git -- 7 --interval 10 --max-polls 1
if [[ "$IS_ROOT" == 0 ]]; then
  mkdir "$STUB/ro2"; chmod 500 "$STUB/ro2"
  out="$(cd "$STUB/nogit" && env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$STUB/ro2" timeout 60 bash "$SUT" 7 --repo acme/widgets --interval 10 --max-polls 1 2>&1)" ; rc=$?
  [[ "$rc" -ne 4 && "$out" == *"monitor-lock: UNAVAILABLE (lock directory unusable"* && "$out" == *"pass ·"* ]] && ok "I6 an unwritable lock dir: UNAVAILABLE line, still polls" || no "I6 unwritable dir" "rc=$rc out=[$out]"
else skip "I6 unwritable lock dir (root; not counted)"; fi
mkdir -p "$STUB/nolib"; cp "$SUT" "$STUB/nolib/monitor-pr-checks.sh"
out="$(cd "$STUB/nogit" && env PATH="$STUB/bin:$PATH" SOLEUR_MONITOR_LOCK_DIR="$(newdir)" timeout 60 bash "$STUB/nolib/monitor-pr-checks.sh" 7 --repo acme/widgets --interval 10 --max-polls 1 2>&1)" ; rc=$?
[[ "$rc" -ne 4 && "$out" == *"monitor-lock: UNAVAILABLE (lib/monitor-lock.sh not found"* && "$out" == *"pass ·"* ]] && ok "I6 an absent lib: UNAVAILABLE line, still polls" || no "I6 absent lib" "rc=$rc out=[$out]"
# origin-derived key == --repo key: a holder on acme/widgets refuses a watch whose repo comes from origin
L="$(newdir)"; hold "$REAL_TREE/lib" "$L" acme/widgets 7 >/dev/null 2>&1; HI=$HP
rc=0; STUB_ORIGIN='https://x-access-token:SECRETTOKEN123@github.com/Acme/Widgets.git' run_tree "$REAL_TREE" "$L" 7 --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 4 ]] && ok "I7 a watch whose repo is derived from origin is refused by a holder armed with --repo" || no "I7 origin == --repo key" "rc=$rc"
rc=0; GH_REPO=Acme/Widgets run_tree "$REAL_TREE" "$L" 7 --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 4 ]] && ok "I7b with no --repo, GH_REPO (the repo gh will poll) keys the lock" || no "I7b GH_REPO key" "rc=$rc"
rc=0; STUB_ORIGIN='gh:acme/widgets' STUB_ORIGIN_URL='https://github.com/Acme/Widgets.git' run_tree "$REAL_TREE" "$L" 7 --interval 10 --max-polls 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 4 ]] && ok "I7c an origin aliased by url.insteadOf is keyed through git remote get-url, not the raw config value" || no "I7c insteadOf origin" "rc=$rc"
unhold "$HI"

# usage errors and --help never touch the lock
L="$(newdir)"; r1=0; r2=0; r3=0
helptxt="$(run_tree "$REAL_TREE" "$L" -h 2>&1)" || r1=$?
run_tree "$REAL_TREE" "$L" abc >/dev/null 2>&1 || r2=$?
run_tree "$REAL_TREE" "$L" --interval 5 7778 >/dev/null 2>&1 || r3=$?
[[ "$r1" -eq 0 && "$r2" -eq 3 && "$r3" -eq 3 && -z "$(ls -A "$L")" ]] && ok "I8 -h / non-numeric PR / --interval 5: rc 0 / 3 / 3 and no link is ever created" || no "I8 usage never locks" "rc=$r1/$r2/$r3 left=$(ls -A "$L")"
[[ "$helptxt" == *"4 when another live monitor"* && "$helptxt" == *"SOLEUR_MONITOR_LOCK=off"* ]] && ok "I9 --help documents rc 4 and the SOLEUR_MONITOR_LOCK bypass" || no "I9 help lists rc 4" "help=[$helptxt]"

# the agent-facing surfaces must name the token the script prints, or a renamed refusal line silently strands them
grep -q 'DUPLICATE MONITOR' "$DIR/soleur/lib/harness.ts" && grep -q 'DUPLICATE MONITOR' "$DIR/soleur/skills/drain-prs/SKILL.md" \
  && ok "I10 harness.ts and drain-prs/SKILL.md both name the DUPLICATE MONITOR token the script prints" || no "I10 rc-4 prose names the refusal token"

# ── Mutation battery: copy -> edit ONE marked line -> the targeted check must report the guard failed ───────────
MUT_N=0; killed=0; mut_skipped=0
mutate() {  # mutate <n> <label> <file: script|lib> <sed-expr> <check>
  local n="$1" label="$2" which="$3" expr="$4" check="$5" T="$STUB/mt.$1" f
  MUT_N=$((MUT_N+1))
  mkdir -p "$T/lib" && cp "$SUT" "$T/monitor-pr-checks.sh" && cp "$LIB" "$T/lib/monitor-lock.sh" || { no "M$n setup failed"; return; }
  if [[ "$which" == script ]]; then f="$T/monitor-pr-checks.sh"; else f="$T/lib/monitor-lock.sh"; fi
  cp "$f" "$f.orig"
  sed -e "$expr" "$f.orig" > "$f" || { no "M$n sed failed"; return; }
  if cmp -s "$f" "$f.orig"; then no "M$n $label: the mutation did NOT land"; return; fi
  if ! bash -n "$f" 2>/dev/null; then no "M$n $label: the mutant does not parse (a crash is not a kill)"; return; fi
  local crc=0; "$check" "$T" || crc=$?
  case "$crc" in
    0) no "M$n $label: SURVIVED (its targeted check still passed)" ;;
    1) killed=$((killed+1)); ok "M$n $label: KILLED by $check" ;;
    *) no "M$n $label: the check's own SETUP failed (rc $crc) — that is a harness failure, not a kill" ;;
  esac
}
mutate 1 "delete the acquire_or_exit call" script '/^acquire_or_exit$/d' chk_refuse
# move: delete the call, re-insert it right after the first poll's `gh pr checks` line
mutate 2 "acquire after the first poll's gh calls" script '/^acquire_or_exit$/d; /checks="\$(gh pr checks/a\
  acquire_or_exit' chk_refuse
mutate 3 "key drops the PR number" lib '/# mut:key/s/+\$pr\.lock/.lock/' chk_keys_pr
mutate 4 "key drops the repo" lib '/# mut:key/s/+\$key+/+/' chk_keys_repo
mutate 5 "liveness drops the lstart comparison" lib '/# mut:lstart/d' chk_lstart
mutate 6 "liveness drops the zombie test" lib '/# mut:zombie/d' chk_zombie
if [[ "$TZ_OK" == 1 ]]; then
  mutate 7 "_ml_ident drops the TZ=UTC pin" lib '/# mut:tz/s/TZ=UTC LC_ALL=C //' chk_tz
else MUT_N=$((MUT_N+1)); mut_skipped=$((mut_skipped+1)); skip "M7 TZ pin mutant (no tz database; not counted)"; fi
mutate 8 "release removes the link unconditionally" lib '/# mut:release-cond/s/.*/  rm -f "$_ML_LINK"/' chk_release
mutate 9 "_cleanup stops calling monitor_lock_release" script '/# mut:cleanup-release/d' chk_cleanup
mutate 10 "add a TERM trap that defers the exit" script '/^trap _cleanup EXIT/s/$/; trap "exit 143" TERM/' chk_term
[[ "$((killed + mut_skipped))" -eq 10 && "$MUT_N" -eq 10 ]] && ok "M* all 10 mutants accounted for ($killed killed, $mut_skipped skipped)" || no "M* mutation battery" "killed=$killed skipped=$mut_skipped of $MUT_N (expected 10)"
# the real tree must pass every shared check (a failing control would make every kill above meaningless)
ctl_bad=""
for c in chk_refuse chk_keys_pr chk_keys_repo chk_lstart chk_zombie chk_release chk_cleanup; do "$c" "$REAL_TREE" || ctl_bad="$ctl_bad $c"; done
[[ -z "$ctl_bad" ]] && ok "M0 control: every targeted check passes on the unmutated tree" || no "M0 control — the battery is void" "failing:$ctl_bad"

# ── Result + anti-vacuity floor ───────────────────────────────────────────────────
printf '\n%s passed, %s failed\n' "$pass_n" "$fail_n"
# FLOOR counts every arm, a skipped one included (each skip() is one arm that could not run on this box), and is the
# exact arm count: raise it in the same edit that adds an arm. Deleting an assertion therefore trips it.
FLOOR=69
_ran=$((pass_n + fail_n + skip_n))
if [[ "$_ran" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran (+%s skipped), floor is %s.\n' "$((pass_n + fail_n))" "$skip_n" "$FLOOR" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran, %s skipped (floor %s)\n' "$((pass_n + fail_n))" "$skip_n" "$FLOOR"
[[ "$fail_n" -eq 0 ]]
