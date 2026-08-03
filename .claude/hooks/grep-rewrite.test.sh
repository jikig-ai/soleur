#!/usr/bin/env bash
# Fixture suite for .claude/hooks/grep-rewrite.sh (issue #7165, ADR-160).
#
# The hook is invoked DIRECTLY — "$HOOK", never `bash "$HOOK"`. Running it via
# an explicit interpreter is the path that makes an exec-bit gate vacuous: the
# suite would stay green against a hook that Claude Code itself could never
# execute. AC9 asserts the mode; this file asserts the mode is USED.
#
# Behavioural cases run the hook's OWN EMITTED STRING, never a re-typed copy.
# A hand-copied expected prefix drifts silently the moment the hook changes;
# extracting it means a prefix change either flows through or reddens AC1a.
#
# `grep` resolution inside the emitted string is observed with a fake `grep`
# BINARY at the front of PATH that prints its exact argv. Asserting on argv is
# what makes AC7 real: a stub that answers identically for every invocation
# cannot tell "no injected flags" from "injected flags ignored".
#
# Pure bash + jq. The test-scripts CI shard has no bun and no node.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/grep-rewrite.sh"

# jq is a PRECONDITION, not a skip. `SKIP … exit 0` reports success having
# asserted nothing, which is the same vacuity this suite exists to prevent —
# and it is reachable on any CI shard that lacks jq.
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing — this suite cannot assert anything without it"; exit 1; }
[[ -x "$HOOK" ]] || { echo "FAIL: $HOOK is not executable — the suite invokes it directly"; exit 1; }

# Floor for the anti-vacuity gate at the bottom of this file. Derived from a
# green run, and a FLOOR rather than an equality so adding an assertion does not
# spuriously red. Raise it when the suite grows.
MIN_ASSERTIONS=60

PASS=0; FAIL=0

# ADR-129 rule (c): ONE owning trap for every tempfile. /tmp is a machine-global
# tmpfs shared with sibling worktrees, so a case dying mid-assertion must not leak.
ROOT="$(mktemp -d -t greprw.XXXXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; shift; local l; for l in "$@"; do echo "  $l"; done; }
want(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "want: $2" "got:  $3"; fi; }

# --- fake `grep` binary: reports argv, so injected flags are directly asserted
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/grep" <<'EOS'
#!/usr/bin/env bash
printf 'ARGV:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
EOS
chmod +x "$ROOT/bin/grep"

# Run the hook from a NON-GIT temp CWD so any branch-dependent sibling logic
# resolves empty and no-ops — a suite that passes on a feature worktree and
# fails on main-CI is the #5192 class. Incidents are sandboxed to the case dir
# so the repo's real .rule-incidents.jsonl is never written.
hook_run() { # <payload> [extra env assignments...]
  local payload="$1"; shift
  local d; d="$(mktemp -d -p "$ROOT")"
  ( cd "$d" && printf '%s' "$payload" | env INCIDENTS_REPO_ROOT="$d" "$@" "$HOOK" 2>/dev/null )
}
hook_rc() { # <payload> [extra env...] -> exit code only
  local payload="$1"; shift
  local d; d="$(mktemp -d -p "$ROOT")"
  ( cd "$d" && printf '%s' "$payload" | env INCIDENTS_REPO_ROOT="$d" "$@" "$HOOK" >/dev/null 2>&1 )
  echo $?
}
payload() { jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
cmd_of()  { jq -r '.hookSpecificOutput.updatedInput.command // ""' <<<"$1"; }

# ===========================================================================
# The prefix, extracted from the hook itself.
# ===========================================================================
MARK='%%%grep%%%'   # must contain `grep` or the hook's gate correctly declines
PREFIX="$(cmd_of "$(hook_run "$(payload "$MARK")")")"
PREFIX="${PREFIX%"$MARK"}"

if [[ -z "$PREFIX" ]]; then
  echo "FAIL: could not extract the prefix — every behavioural case below would be vacuous"
  exit 1
fi
ok "prefix extracted from the hook's own output (${#PREFIX} bytes)"

# Non-vacuity control for the whole behavioural block: WITHOUT the prefix the
# shim must win. If this ever passes, the harness is not testing the prefix.
mkshim() { printf '%s\n' 'function grep { echo SHIM-CALLED-ugrep; }' > "$1"; }
runsh() { # <prelude-file> <command text>  -> stdout
  local f; f="$(mktemp -p "$ROOT")"
  cat "$1" > "$f"; printf '%s\n' "$2" >> "$f"
  PATH="$ROOT/bin:$PATH" bash --noprofile --norc "$f" 2>&1
}
SHIMF="$(mktemp -p "$ROOT")"; mkshim "$SHIMF"
want "control: without the prefix the shim wins (harness is live)" \
  "SHIM-CALLED-ugrep" "$(runsh "$SHIMF" 'grep -rn foo .')"

# ===========================================================================
# AC1a — byte-exact emitted command
# ===========================================================================
# The expected prefix is written out IN FULL, not derived. This is the one
# place a literal belongs: it is the drift guard. Any change to the hook's
# injected flags or bypass arms must be a deliberate edit here too.
EXPECTED_PREFIX='grep(){ local _soleur_grep_rw; for _soleur_grep_rw in "$@"; do case "$_soleur_grep_rw" in -*-filter*|-*-pager*|-*-view*|-*-format-open*|-*-config*|---*|-@*|-*-save-config*|-[Zz]*|-[!-]*[Zz]*|--null|--null-data) command grep "$@"; return;; esac; done; command grep -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude=.env "$@"; }; '
want "AC1a prefix is byte-exact" "$EXPECTED_PREFIX" "$PREFIX"
want "AC1a emitted command is prefix + ORIGINAL, byte-identical remainder" \
  "${EXPECTED_PREFIX}grep -rn 'a b|c' \"\$X\" # trailing" \
  "$(cmd_of "$(hook_run "$(payload "grep -rn 'a b|c' \"\$X\" # trailing")")")"

# ===========================================================================
# AC3 — no permissionDecision at any depth; no top-level decision/continue
# ===========================================================================
# Asserted on the NON-EMPTY and EMPTY cases SEPARATELY: `jq -e` exits 4 on
# empty stdin, so a single combined assertion passes vacuously for the case
# that emits nothing.
OUT_NONEMPTY="$(hook_run "$(payload 'grep foo')")"
want "AC3 non-empty: no permissionDecision key at any depth" "0" \
  "$(jq -c '[paths | map(tostring) | index("permissionDecision")] | map(select(. != null)) | length' <<<"$OUT_NONEMPTY")"
want "AC3 non-empty: no top-level decision" "null" "$(jq -c '.decision' <<<"$OUT_NONEMPTY")"
want "AC3 non-empty: no top-level continue" "null" "$(jq -c '.continue' <<<"$OUT_NONEMPTY")"
want "AC3 non-empty: hookEventName rides in the same object as updatedInput" "PreToolUse" \
  "$(jq -r '.hookSpecificOutput | select(has("updatedInput")) | .hookEventName' <<<"$OUT_NONEMPTY")"
want "AC3 empty case: non-grep command emits literally nothing" "0" \
  "$(printf '%s' "$(hook_run "$(payload 'echo hi')")" | wc -c | tr -d ' ')"

# ===========================================================================
# AC4 — every tool_input sibling key survives (updatedInput REPLACES, measured)
# ===========================================================================
FULL="$(jq -nc '{tool_name:"Bash", tool_input:{command:"grep x", description:"d",
        timeout:45000, run_in_background:true, sandbox:false}}')"
OUT_FULL="$(hook_run "$FULL")"
want "AC4 description survives"       '"d"'   "$(jq -c '.hookSpecificOutput.updatedInput.description' <<<"$OUT_FULL")"
want "AC4 timeout survives"           '45000' "$(jq -c '.hookSpecificOutput.updatedInput.timeout' <<<"$OUT_FULL")"
want "AC4 run_in_background survives" 'true'  "$(jq -c '.hookSpecificOutput.updatedInput.run_in_background' <<<"$OUT_FULL")"
want "AC4 sandbox survives (false, not dropped by a falsy default)" 'false' \
  "$(jq -c '.hookSpecificOutput.updatedInput.sandbox' <<<"$OUT_FULL")"
want "AC4 no key is invented or lost" '["command","description","run_in_background","sandbox","timeout"]' \
  "$(jq -c '.hookSpecificOutput.updatedInput | keys' <<<"$OUT_FULL")"

# ===========================================================================
# AC6 — the seven resolution forms, including the two v1 called unfixable
# ===========================================================================
ac6_case() { # <label> <command> <expect-substring-in-output>
  local out; out="$(runsh "$SHIMF" "${PREFIX}$2")"
  case "$out" in
    *"$3"*) ok "AC6 $1" ;;
    *) bad "AC6 $1" "want output containing: $3" "got: $out" ;;
  esac
}
ac6_case "direct invocation"                'grep alpha'                  'ARGV:'
ac6_case "pipeline element"                 'echo x | grep alpha'         'ARGV:'
ac6_case "command substitution"             'echo "r=$(grep alpha)"'      'r=ARGV:'
ac6_case "backtick substitution"            'echo "r=`grep alpha`"'       'r=ARGV:'
ac6_case "subshell"                         '( grep alpha )'              'ARGV:'
ac6_case "variable indirection (v1: unfixable)" 'G=grep; $G alpha'        'ARGV:'
ac6_case "eval (v1: unfixable)"             'eval "grep alpha"'           'ARGV:'
# The shim must never be reached in any of the seven. The summary `ok` below is
# CONDITIONAL on a loop-local flag — an unconditional `ok` after a loop that can
# call `bad` prints PASS on a run that just failed.
shim_hits=0
for f in 'grep alpha' 'echo x | grep alpha' 'echo "r=$(grep alpha)"' \
         'echo "r=`grep alpha`"' '( grep alpha )' 'G=grep; $G alpha' 'eval "grep alpha"'; do
  out="$(runsh "$SHIMF" "${PREFIX}$f")"
  case "$out" in *SHIM-CALLED*) bad "AC6 shim reached by: $f" "got: $out"; shim_hits=$((shim_hits+1)) ;; esac
done
[[ "$shim_hits" -eq 0 ]] && ok "AC6 shim reached by none of the seven resolution forms"

# ===========================================================================
# AC7 — all 12 shim bypass arms receive `command grep "$@"` with NO injected flags
# ===========================================================================
# One representative flag per arm of the live shim's case statement, in order.
ARMS=(
  '--filter=x'        # -*-filter*
  '--pager'           # -*-pager*
  '--view'            # -*-view*
  '--format-open=x'   # -*-format-open*
  '--config=x'        # -*-config*
  '---help'           # ---*
  '-@x'               # -@*
  '--save-config'     # -*-save-config*
  '-Z'                # -[Zz]*
  '-rZ'               # -[!-]*[Zz]*
  '--null'            # --null
  '--null-data'       # --null-data
)
arms_clean=0
for a in "${ARMS[@]}"; do
  out="$(runsh "$SHIMF" "${PREFIX}grep $a needle")"
  if [[ "$out" == "ARGV: [$a] [needle]" ]]; then
    arms_clean=$((arms_clean+1))
  else
    bad "AC7 bypass arm '$a' must get no injected flags" "got: $out"
  fi
done
want "AC7 all ${#ARMS[@]} representatives pass through unmodified" "${#ARMS[@]}" "$arms_clean"

# ARM REACHABILITY. The label "all 12 arms" overclaimed: 12 representatives do
# not imply 12 distinct arms fire, because `case` takes the FIRST match. This
# loop reports which pattern each representative actually lands on.
#
# MEASURED RESULT: arm 8 `-*-save-config*` is UNREACHABLE — `--save-config`
# matches arm 5 `-*-config*` first. That is true of the LIVE SHIM TOO (same
# ordering), so the dead arm is faithfully mirrored, and this suite deliberately
# does NOT "fix" it: byte-exactness with the vendor's shim is the invariant the
# whole design rests on, and diverging to prune a dead arm would break it.
PATTERNS=( '-*-filter*' '-*-pager*' '-*-view*' '-*-format-open*' '-*-config*' '---*'
           '-@*' '-*-save-config*' '-[Zz]*' '-[!-]*[Zz]*' '--null' '--null-data' )
reached=""
for a in "${ARMS[@]}"; do
  idx=0
  for p in "${PATTERNS[@]}"; do
    idx=$((idx+1))
    # shellcheck disable=SC2254  # $p is a case pattern by design
    case "$a" in $p) reached="$reached $idx"; break ;; esac
  done
done
uniq_reached="$(printf '%s\n' $reached | sort -un | tr '\n' ' ' | sed 's/ $//')"
want "AC7 representatives resolve to arms (8 absent: subsumed by 5, as in the shim)" \
  "1 2 3 4 5 6 7 9 10 11 12" "$uniq_reached"
# Every representative must land on SOME arm, or it is not testing a bypass.
want "AC7 every representative matched a bypass pattern" "${#ARMS[@]}" \
  "$(printf '%s\n' $reached | grep -c . || true)"

# Positive control: a NON-bypass flag MUST receive the injected set. Without
# this, an always-bypass regression would leave every AC7 case green.
want "AC7 control: a non-bypass call DOES get the injected flags" \
  "ARGV: [-I] [--exclude-dir=.git] [--exclude-dir=.svn] [--exclude-dir=.hg] [--exclude-dir=.bzr] [--exclude-dir=.jj] [--exclude-dir=.sl] [--exclude-dir=node_modules] [--exclude-dir=dist] [--exclude-dir=.next] [--exclude=.env] [-rn] [needle]" \
  "$(runsh "$SHIMF" "${PREFIX}grep -rn needle")"

# ===========================================================================
# AC10 — fail-open triad. A PreToolUse hook exiting non-zero BLOCKS the call,
# and this hook runs on 100% of Bash calls.
# ===========================================================================
BIG="$(mktemp -p "$ROOT")"; head -c 1048576 /dev/urandom > "$BIG"
failopen() { # <label> <payload>
  local rc out
  rc="$(hook_rc "$2")"
  out="$(hook_run "$2")"
  if [[ "$rc" == "0" && -z "$out" ]]; then ok "AC10 $1 → exit 0, empty stdout"
  else bad "AC10 $1" "rc=$rc (want 0)" "stdout=${out:0:120} (want empty)"; fi
}
failopen "empty stdin"                 ""
failopen "non-JSON garbage"            'garbage {{'
failopen "JSON with no .tool_input"    '{"tool_name":"Bash"}'
failopen "1 MB binary garbage"         "$(cat "$BIG")"
failopen "non-string command (array)"  "$(jq -nc '{tool_input:{command:["git","stash"]}}')"
failopen "non-object tool_input"       "$(jq -nc '{tool_input:"grep foo"}')"
failopen "non-object root"             "$(jq -nc '["grep"]')"

# jq unusable. The shim must be EXECUTABLE: `command -v jq` tests executability,
# so a chmod -x stub is skipped and the REAL jq is found further down PATH — the
# fixture then passes against a hook that never met the condition it names.
# (Measured: that form emitted a full envelope and the case still read green.)
mkdir -p "$ROOT/badjq"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$ROOT/badjq/jq"; chmod +x "$ROOT/badjq/jq"
rc_nojq="$(hook_rc "$(payload 'grep foo')" PATH="$ROOT/badjq:$PATH")"
out_nojq="$(hook_run "$(payload 'grep foo')" PATH="$ROOT/badjq:$PATH")"
if [[ "$rc_nojq" == "0" && -z "$out_nojq" ]]; then ok "AC10 jq exits non-zero → exit 0, empty stdout"
else bad "AC10 jq exits non-zero" "rc=$rc_nojq" "stdout=${out_nojq:0:120}"; fi

# jq present, exit 0, but emitting NON-JSON. The dangerous shape: if the hook
# trusted jq's exit code it would print the garbage as an envelope.
mkdir -p "$ROOT/junkjq"
printf '%s\n' '#!/usr/bin/env bash' 'echo "not json at all"' 'exit 0' > "$ROOT/junkjq/jq"
chmod +x "$ROOT/junkjq/jq"
rc_junk="$(hook_rc "$(payload 'grep foo')" PATH="$ROOT/junkjq:$PATH")"
out_junk="$(hook_run "$(payload 'grep foo')" PATH="$ROOT/junkjq:$PATH")"
if [[ "$rc_junk" == "0" && -z "$out_junk" ]]; then ok "AC10 jq emits garbage at rc 0 → exit 0, empty stdout"
else bad "AC10 jq emits garbage at rc 0" "rc=$rc_junk" "stdout=${out_junk:0:120}"; fi

# perl absent: this design does not parse and never invokes perl. Asserted as a
# MECHANISM BAN rather than a runtime fixture — a runtime probe would pass
# whether or not perl were reachable, which is the vacuous form.
want "AC10 the hook invokes no perl (v2 does not parse)" "0" \
  "$(awk '!/^[[:space:]]*#/' "$HOOK" | grep -cE '(^|[^[:alnum:]_])perl([^[:alnum:]_]|$)' || true)"
# POSITIVE CONTROL. The count above is 0 for a hook with no perl AND for no
# input at all (a renamed file, a broken awk). Without this, the assertion is
# satisfied by absence-of-input rather than absence-of-perl.
printf '%s\n' '#!/usr/bin/env bash' 'perl -e "print 1"' > "$ROOT/perl-decoy.sh"
want "AC10 control: the perl detector finds perl when it is present" "1" \
  "$(awk '!/^[[:space:]]*#/' "$ROOT/perl-decoy.sh" | grep -cE '(^|[^[:alnum:]_])perl([^[:alnum:]_]|$)' || true)"

# ===========================================================================
# AC11 — idempotency / fixed point
# ===========================================================================
ONCE="$(cmd_of "$(hook_run "$(payload 'grep foo')")")"
TWICE_OUT="$(hook_run "$(payload "$ONCE")")"
want "AC11 applying the hook to its own output emits nothing" "0" \
  "$(printf '%s' "$TWICE_OUT" | wc -c | tr -d ' ')"
want "AC11 exactly one prefix in the once-rewritten command" "1" \
  "$(awk -v s='local _soleur_grep_rw' 'BEGIN{n=0} {n+=gsub(s,s)} END{print n}' <<<"$ONCE")"

# ===========================================================================
# AC12 — kill switch, read before any subprocess or lib sourcing
# ===========================================================================
rc_ks="$(hook_rc "$(payload 'grep foo')" SOLEUR_DISABLE_GREP_REWRITE=1)"
out_ks="$(hook_run "$(payload 'grep foo')" SOLEUR_DISABLE_GREP_REWRITE=1)"
if [[ "$rc_ks" == "0" && -z "$out_ks" ]]; then ok "AC12 kill switch disables the rewrite"
else bad "AC12 kill switch" "rc=$rc_ks" "stdout=${out_ks:0:120}"; fi
# It must be the FIRST executable statement. Fixture: a copy of the hook whose
# sibling lib/ does not exist. With the switch ON it must return BEFORE the
# source is attempted — asserted on STDERR being empty, not just on rc, since
# both paths exit 0 and rc alone cannot tell them apart.
#
# (An earlier form stripped PATH to a dir with no `jq`. That yields rc=127
# because `#!/usr/bin/env bash` can no longer find bash — it measures the
# shebang, not the hook.)
mkdir -p "$ROOT/nolib"; cp "$HOOK" "$ROOT/nolib/grep-rewrite.sh"; chmod +x "$ROOT/nolib/grep-rewrite.sh"
nolib_err_on="$( cd "$ROOT" && printf '%s' "$(payload 'grep foo')" \
  | env SOLEUR_DISABLE_GREP_REWRITE=1 "$ROOT/nolib/grep-rewrite.sh" 2>&1 >/dev/null )"
want "AC12 switch ON returns before sourcing (no stderr from a missing lib/)" "" "$nolib_err_on"
# Non-vacuity: with the switch OFF the same lib-less copy MUST complain, or the
# fixture proves nothing about ordering.
nolib_err_off="$( cd "$ROOT" && printf '%s' "$(payload 'grep foo')" \
  | env "$ROOT/nolib/grep-rewrite.sh" 2>&1 >/dev/null )"
case "$nolib_err_off" in
  *"helper missing"*) ok "AC12 control: switch OFF on a lib-less copy does complain" ;;
  *) bad "AC12 control: switch OFF must complain about the missing helper" "got: ${nolib_err_off:0:160}" ;;
esac
# Non-vacuity: the switch OFF must still produce output for the same payload.
want "AC12 control: switch off still rewrites" "1" \
  "$(out="$(hook_run "$(payload 'grep foo')")"; [[ -n "$out" ]] && echo 1 || echo 0)"

# ===========================================================================
# AC1b — the emitted string is cheap. The shim is NOT reached.
# ===========================================================================
# The reproducer class from #7163: two bounded repeats over a WIDE atom with a
# literal between them that OCCURS in the subject. Under ugrep this reached
# 9.5 GB RSS; GNU grep runs it in ~7 MB / 0.1 s.
#
# Capped with `ulimit -v` + `timeout` per the standing rule — the reproducer is
# never run uncapped. The shim stand-in writes a marker instead of allocating,
# so the assertion is "the shim was bypassed" rather than "the box survived",
# which is both safe and directly observable.
FIX="$ROOT/fixture.txt"
i=0; : > "$FIX"
while [[ $i -lt 400 ]]; do printf 'lorem ipsum q dolor sit amet 0123456789 %s\n' "$i" >> "$FIX"; i=$((i+1)); done
MARKER="$ROOT/shim-was-reached"
SHIM2="$(mktemp -p "$ROOT")"
printf '%s\n' "function grep { : > '$MARKER'; echo SHIM-CALLED-ugrep; }" > "$SHIM2"
# `-E` IS LOAD-BEARING. GNU grep defaults to BRE, where `{0,16}` is literal text
# and the pattern matches nothing — so without -E this measured a zero-match
# linear scan and the "cheap" assertion proved nothing about the pathological
# path. Under -E it compiles two bounded repeats over a wide atom with a literal
# between them that OCCURS in the subject, which is the #7163 blowup class.
REPRO_CMD="$(cmd_of "$(hook_run "$(payload "grep -Ec '.{0,16}q[^.]{0,16}' '$FIX'")")")"
[[ -n "$REPRO_CMD" ]] || bad "AC1b could not build the reproducer command — the cases below would be vacuous"
SCRIPT2="$(mktemp -p "$ROOT")"
cat "$SHIM2" > "$SCRIPT2"; printf '%s\n' "$REPRO_CMD" >> "$SCRIPT2"
t0=$(date +%s%N)
( ulimit -v 2000000; timeout 20 bash --noprofile --norc "$SCRIPT2" ) >/dev/null 2>&1
rc_repro=$?
t1=$(date +%s%N); ms=$(( (t1-t0)/1000000 ))
# rc IS PINNED. With the script absent the run yields rc=127 and no marker, and
# BOTH assertions below would read green — a reproducer that never executed is
# indistinguishable from one that passed. 0 = matches found (expected here).
want "AC1b reproducer actually executed and matched (rc pinned, not merely non-124)" "0" "$rc_repro"
if [[ -e "$MARKER" ]]; then bad "AC1b shim was reached by the rewritten reproducer"
else ok "AC1b shim NOT reached by the rewritten reproducer"; fi
# 124 = timeout, 137 = SIGKILL (OOM). Either means the cost profile did not change.
if [[ "$rc_repro" == "124" || "$rc_repro" == "137" ]]; then
  bad "AC1b rewritten reproducer did not complete in budget" "rc=$rc_repro after ${ms}ms"
else
  ok "AC1b rewritten reproducer completed under ulimit -v 2000000 in ${ms}ms (rc=$rc_repro)"
fi
# Positive control for the marker mechanism: the UNPREFIXED command must reach
# the shim and write the marker. Without this, "marker absent" is satisfied by a
# marker mechanism that never works.
rm -f "$MARKER"
SCRIPT2C="$(mktemp -p "$ROOT")"
cat "$SHIM2" > "$SCRIPT2C"; printf "grep -Ec 'q' '%s'\n" "$FIX" >> "$SCRIPT2C"
( ulimit -v 2000000; timeout 20 bash --noprofile --norc "$SCRIPT2C" ) >/dev/null 2>&1
if [[ -e "$MARKER" ]]; then ok "AC1b control: the UNPREFIXED command does reach the shim (marker mechanism works)"
else bad "AC1b control: unprefixed command did not reach the shim — the marker assertion above is vacuous"; fi
if command -v /usr/bin/time >/dev/null 2>&1; then
  peak_kb="$( ( ulimit -v 2000000; /usr/bin/time -f '%M' timeout 20 bash --noprofile --norc "$SCRIPT2" ) 2>&1 >/dev/null | tail -1 )"
  case "$peak_kb" in
    ''|*[!0-9]*) echo "SKIP: could not read peak RSS (got '${peak_kb:0:40}')" ;;
    *) if [[ "$peak_kb" -lt 102400 ]]; then ok "AC1b peak RSS ${peak_kb} KB < 100 MB"
       else bad "AC1b peak RSS ${peak_kb} KB >= 100 MB"; fi ;;
  esac
fi

# ===========================================================================
# AC17 — hot-path cost, asserted RELATIVE to a hook already on this path
# ===========================================================================
# The plan specified an absolute p95 < 50 ms. Measurement refutes that as a
# target rather than as a result: on this machine a bare `bash -c true` is
# 14 ms, one jq fork is 20 ms, and EVERY sibling PreToolUse Bash hook already
# registered costs 103-124 ms p95 on the same payload. No hook in this repo
# that sources the input helper and forks jq can reach 50 ms, so an absolute
# 50 ms gate would red on a correct implementation.
#
# The property that actually matters is that this hook does not make the hot
# path worse than what is already on it. Asserted relatively, which also makes
# the gate machine-independent — an absolute millisecond bound is exactly the
# shape that flakes on a slower CI runner.
BIGCMD="grep -rn needle . $(head -c 4000 /dev/zero | tr '\0' 'x')"
BIGPAY="$(payload "$BIGCMD")"
lat_dir="$(mktemp -d -p "$ROOT")"
bench_hook() { # <path-to-hook> -> p95 ms over 15 reps
  local h="$1" n=0 s e; local -a t=()
  while [[ $n -lt 15 ]]; do
    s=$(date +%s%N)
    ( cd "$lat_dir" && printf '%s' "$BIGPAY" | env INCIDENTS_REPO_ROOT="$lat_dir" "$h" >/dev/null 2>&1 )
    e=$(date +%s%N); t+=( $(( (e-s)/1000000 )) ); n=$((n+1))
  done
  printf '%s\n' "${t[@]}" | sort -n | awk 'NR==14{print}'
}
# MECHANISM GATE, NOT A WALL-CLOCK GATE.
#
# The wall-clock form this replaced was defective three ways, all measured:
# it benchmarked the two arms in separate blocks (non-interleaved — demonstrated
# to bias the comparison by up to 6x on this machine), `awk NR==14` of 15 sorted
# samples is ~p93 not p95, and a purely relative bound passes trivially if the
# sibling regresses. It also flaked ~16% of runs with the hook unmutated.
#
# `lib/hook-input.sh` states the principle this now follows: "a mechanism ban is
# deterministic where a wall-clock comparison is not." Fork COUNT is the property
# the latency gate was only ever a proxy for, and it is exact.
#
# (Hooks were also measured to run in PARALLEL — 19 hooks 259 ms vs 18 hooks
# 281 ms, i.e. this hook's marginal wall-clock cost is indistinguishable from
# zero. That is another reason a timing gate here pins nothing an operator feels.)
FORKLOG="$ROOT/forks.log"
mkdir -p "$ROOT/forkbin"
for tool in jq cat; do
  real="$(command -v "$tool")"
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %s >> "%s"\n' "$tool" "$FORKLOG"
    printf 'exec %s "$@"\n' "$real"
  } > "$ROOT/forkbin/$tool"
  chmod +x "$ROOT/forkbin/$tool"
done
count_forks() { # <payload> -> "<jq-count> <cat-count>"
  : > "$FORKLOG"
  local d; d="$(mktemp -d -p "$ROOT")"
  ( cd "$d" && printf '%s' "$1" | env PATH="$ROOT/forkbin:$PATH" INCIDENTS_REPO_ROOT="$d" "$HOOK" >/dev/null 2>&1 )
  printf '%s %s' "$(grep -c '^jq$' "$FORKLOG" || true)" "$(grep -c '^cat$' "$FORKLOG" || true)"
}
GREP_FORKS="$(count_forks "$(payload 'grep -rn needle .')")"
NOGREP_FORKS="$(count_forks "$(payload 'ls -la /tmp')")"
echo "  (forks — grep path: ${GREP_FORKS} [jq cat]; non-grep path: ${NOGREP_FORKS})"
# Grep path: one jq to parse (the shared ADR-156 program), one to build the
# envelope, one to validate it. Non-grep path must not pay the envelope forks.
want "AC17 grep path forks jq exactly 3 times (parse + build + validate)" "3 1" "$GREP_FORKS"
want "AC17 non-grep path forks jq exactly once (parse only)" "1 1" "$NOGREP_FORKS"
# incidents.sh must never be sourced on the happy path — it is ~18 kB and this
# hook runs on 100% of Bash calls.
want "AC17 happy path does not source incidents.sh" "0" \
  "$(awk '!/^[[:space:]]*#/' "$HOOK" | grep -c 'source .*incidents\.sh' | awk '{print ($1>1)?1:0}')"

# ===========================================================================
# .env excludes — alignment with the already-declared Read(**/.env) deny
# ===========================================================================
# Exact name only — the ".env.*" glob form was reverted because it excluded the
# tracked .env.example files. This asserts the collateral is gone.
envdir="$(mktemp -d -p "$ROOT")"
printf 'SENTRY_ISSUE_RW_TOKEN=x\n' > "$envdir/.env.example"
want ".env.example is NOT excluded (it is tracked and deliberately published)" "1" \
  "$( cd "$envdir" && bash --noprofile --norc -c "${PREFIX}grep -c SENTRY_ISSUE_RW_TOKEN .env.example" )"
# Behavioural: a recursive grep must not surface the gitignored .env, and this
# is the incidental path the change is aimed at.
secretdir="$(mktemp -d -p "$ROOT")"
printf 'SUPABASE_SERVICE_ROLE_KEY=shhh\n' > "$secretdir/.env"
printf 'harmless\n' > "$secretdir/app.ts"
realpfx_out="$( cd "$secretdir" && bash --noprofile --norc -c "${PREFIX}grep -rn SUPABASE . 2>&1"; echo "rc=$?" )"
want ".env is NOT surfaced by a recursive grep (the incidental path)" "rc=1" "$realpfx_out"
# Positive control: the same tree WITHOUT the prefix does surface it, or the
# assertion above is satisfied by an empty tree rather than by the excludes.
ctl_out="$( cd "$secretdir" && bash --noprofile --norc -c 'command grep -rn SUPABASE . 2>&1' | grep -c 'SUPABASE' || true )"
want ".env control: without the excludes the same tree DOES surface it" "1" "$ctl_out"
# The evasions are ASSERTED, not merely commented. If a future change closes one,
# the fixture reddens and the limits block must be re-derived rather than
# silently going stale.
evdir="$(mktemp -d -p "$ROOT")"
printf 'SECRET=abc\n' > "$evdir/.env"; printf 'plain\n' > "$evdir/app.ts"
want "LIMIT 1: --include wins over the prepended exclude (argv order)" "0" \
  "$( cd "$evdir" && bash --noprofile --norc -c "${PREFIX}grep -rn SECRET . --include=.env >/dev/null 2>&1; echo \$?" )"
( cd "$evdir" && ln -sf .env harmless.txt )
want "LIMIT 2: --exclude matches the link NAME, not the target" "0" \
  "$( cd "$evdir" && bash --noprofile --norc -c "${PREFIX}grep -Rn SECRET harmless.txt >/dev/null 2>&1; echo \$?" )"
printf 'SECRET=def\n' > "$evdir/.env.local"
want "LIMIT 4: only the exact name .env is excluded (.env.local reachable)" "0" \
  "$( cd "$evdir" && bash --noprofile --norc -c "${PREFIX}grep -rn SECRET .env.local >/dev/null 2>&1; echo \$?" )"

# ===========================================================================
# Branches that had ZERO coverage until review found them
# ===========================================================================
# Each of the three below could be deleted or neutered with the whole suite
# green. They are the hook's telemetry and mode surfaces — the parts that only
# matter when something has already gone wrong, which is exactly why nothing
# exercised them.

# --- observe-only mode (the wg-dark-launch-deploy-gates mechanism) ----------
obs_dir="$(mktemp -d -p "$ROOT")"
obs_out="$( cd "$obs_dir" && printf '%s' "$(payload 'grep -rn foo .')" \
  | env INCIDENTS_REPO_ROOT="$obs_dir" SOLEUR_GREP_REWRITE_OBSERVE=1 "$HOOK" 2>/dev/null )"
want "observe mode emits NO envelope" "0" "$(printf '%s' "$obs_out" | wc -c | tr -d ' ')"
want "observe mode records grep-rewrite-would-rewrite" "1" \
  "$(jq -r 'select(.rule_id=="grep-rewrite-would-rewrite")|.rule_id' "$obs_dir/.claude/.rule-incidents.jsonl" 2>/dev/null | grep -c . || true)"
# Control: the SAME payload without the env var must emit an envelope and no row.
ctl_dir="$(mktemp -d -p "$ROOT")"
ctl_out="$( cd "$ctl_dir" && printf '%s' "$(payload 'grep -rn foo .')" \
  | env INCIDENTS_REPO_ROOT="$ctl_dir" "$HOOK" 2>/dev/null )"
want "observe control: without the flag an envelope IS emitted" "1" \
  "$([[ -n "$ctl_out" ]] && echo 1 || echo 0)"
want "observe control: without the flag NO would-rewrite row is written" "0" \
  "$(jq -r 'select(.rule_id=="grep-rewrite-would-rewrite")|.rule_id' "$ctl_dir/.claude/.rule-incidents.jsonl" 2>/dev/null | grep -c . || true)"

# --- the tool_name gate ----------------------------------------------------
want "non-Bash tool_name is declined (matcher is not a verifiable invariant — ADR-156)" "0" \
  "$(printf '%s' "$(hook_run "$(jq -nc '{tool_name:"Write", tool_input:{command:"grep foo"}}')")" | wc -c | tr -d ' ')"

# --- parse-failure telemetry (ADR-160 clause 7 claims this row exists) -----
pf_dir="$(mktemp -d -p "$ROOT")"
( cd "$pf_dir" && printf 'garbage {{' | env INCIDENTS_REPO_ROOT="$pf_dir" "$HOOK" >/dev/null 2>&1 )
want "parse failure records a hook-input-* row attributed to this hook" "1" \
  "$(jq -r 'select(.rule_id|startswith("hook-input-"))|.command_snippet' "$pf_dir/.claude/.rule-incidents.jsonl" 2>/dev/null | grep -c 'hook=grep-rewrite' || true)"

# ===========================================================================
# Large commands — the MAX_ARG_STRLEN regression
# ===========================================================================
# `jq --arg` carrying prefix+command as ONE argv entry hit Linux
# MAX_ARG_STRLEN (131072): bisected at a 453-byte prefix to 453 + 130,619 =
# 131,072 (the threshold moves with the prefix), so every command
# at or above 130,619 bytes silently failed to rewrite. Fail-open, so nothing
# broke — it just stopped working, on exactly the heredoc-shaped calls most
# likely to be large. The fix passes only the constant prefix through argv.
big_dir="$(mktemp -d -p "$ROOT")"
{ printf 'grep foo '; head -c 200000 /dev/zero | tr '\0' 'x'; } > "$big_dir/cmd.txt"
jq -Rs '{tool_name:"Bash", tool_input:{command:., timeout:7}}' < "$big_dir/cmd.txt" > "$big_dir/payload.json"
big_out="$( cd "$big_dir" && env INCIDENTS_REPO_ROOT="$big_dir" "$HOOK" < "$big_dir/payload.json" 2>/dev/null )"
want "200 kB command still rewrites (argv limit is structurally unreachable)" "1" \
  "$([[ -n "$big_out" ]] && echo 1 || echo 0)"
printf '%s' "$big_out" | jq -r '.hookSpecificOutput.updatedInput.command' > "$big_dir/got.txt"
# jq -r appends a trailing newline; compare against the fixture plus that byte.
{ cat "$big_dir/cmd.txt"; printf '\n'; } > "$big_dir/want-tail.txt"
if cmp -s <(tail -c +"$(( ${#EXPECTED_PREFIX} + 1 ))" "$big_dir/got.txt") "$big_dir/want-tail.txt"; then
  ok "200 kB command survives byte-exact after the prefix"
else
  bad "200 kB command was altered beyond the prefix"
fi
want "200 kB rewrite preserves sibling keys" "7" \
  "$(printf '%s' "$big_out" | jq -r '.hookSpecificOutput.updatedInput.timeout')"

# ===========================================================================
# Gate behaviour — the sloppy gate is sloppy in the SAFE direction only
# ===========================================================================
want "gate: non-grep command is left entirely alone" "0" \
  "$(printf '%s' "$(hook_run "$(payload 'ls -la /tmp && echo done')")" | wc -c | tr -d ' ')"
for c in 'git grep foo' 'pgrep -f node' 'echo "the word grep in data"' 'rg foo | xargs grep bar'; do
  got="$(cmd_of "$(hook_run "$(payload "$c")")")"
  want "gate: '$c' keeps its command byte-identical after the prefix" "${EXPECTED_PREFIX}${c}" "$got"
done

echo
echo "=== grep-rewrite: ${PASS} passed, ${FAIL} failed ==="

# ANTI-VACUITY FLOOR. Gating only on `FAIL -eq 0` is satisfied by a suite that
# ran ZERO assertions: neutering ok/bad/want to no-ops printed
# "0 passed, 0 failed" and exited 0 (measured). Nothing above pins that the
# assertions executed at all, so the floor is the only thing that can.
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only ${PASS} assertions ran (floor ${MIN_ASSERTIONS}) — the suite went vacuous."
  echo "      A suite that asserts nothing exits 0 on FAIL-count alone; this floor is what stops that."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
