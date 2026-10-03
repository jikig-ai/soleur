#!/usr/bin/env bash
# audit-suite-reads.sh — record which repo files each registered suite OPENS, and decide whether a
# suite may leave the always-on set (#9307, PR-B / B1). Operator tooling: Linux only, never run in CI.
#
# Usage:
#   audit-suite-reads.sh record  [--rev REV] [--repo DIR] [--only LABEL[,LABEL...]] [--mode demote|check]
#                                [--cover-from-selection] [--max-load N] [--timeout S] [--reps N]
#                                [--out DIR] [--allow-unresolved-probes]
#   audit-suite-reads.sh verdict --events F --reader-err F --meta F --root DIR [--mode demote|check]
#                                [--allow-unresolved-probes]
#   audit-suite-reads.sh --help
#
# HOW IT WORKS. `record` materialises REV with `git archive` into a private 0700 directory, gives it its
# own `git init` (a `git worktree` would share .git with the live repo), enumerates the registered suites
# there (`test-all.sh --enumerate-commands all`) and runs each one TWICE, serially, from the checkout root
# under `env -i` (scratch HOME/TMPDIR, a scratch PATH that is the ENTIRE PATH, no network: `unshare -rn`,
# else `bwrap --unshare-net`; the recorder refuses to start when neither exists), each in its own setsid
# process group. scripts/lib/inotify-open-recorder.py watches the checkout and writes one line per OPEN;
# a nonce-named sentinel file opened before and after each run cuts the stream into per-run windows IN
# EVENT ORDER. The one `verdict()` function below turns events + reader stderr + exit codes + cover into a
# row; live `record` and replayed `verdict` call the same function.
#
# COVER. With --cover-from-selection the cover of a label is its anchored edge set from
# `test-all.sh --print-selection --paths=README.md` run IN THE AUDITED CHECKOUT (declared plus derived: the
# set the gate really uses); the suite's own argv files are always covered. A candidate demotion is audited
# by applying the proposed lib edit inside the checkout first. The cover is static suite text, not the
# observed reads, so the comparison is not tautological.
#
# VERDICTS. demote mode: demotable | uncovered | disqualified | unreliable. check mode (the 16 rows whose
# closure reaches the runner): covered | uncovered | unreliable, never demotable; size caps, probe findings
# and the carried-disqualifier table are reported as `detail=` information only.
#   unreliable   recording incomplete or unstable (retry, never a change of classification): IN_Q_OVERFLOW in
#                the window or the gap after it, `Failed to watch`, reader not ready, rc != 0 (124 = cap),
#                load refusal, contamination of the checkout, repeat disagreement, sentinel or event damage.
#   disqualified a file test/stat/ls/find operand outside the cover, a hit in the carried regex table (git
#                history/tree walks, origin/main, --changed/--base, network, clock), a directory created
#                mid-run, a size cap (8 second-level dirs, 700 files, cover of 14 edges), or no scannable file.
#   uncovered    opens outside the cover (listed).
# Exit: 0 every row decided and none unreliable; 2 usage; 3 at least one row unreliable (table still
# written); 4 zero suites enumerated, or zero windows recorded.
#
# BLIND SPOTS (evidence for the run that happened, not a proof for every input):
#   - probes of missing files (`[[ -e missing ]]`) and `stat` produce no open event; only the static scan of
#     the suite file sees them (and it cannot resolve $VAR operands, which therefore disqualify unless
#     --allow-unresolved-probes);
#   - directories created mid-run are not watched (the reader reports them; they disqualify);
#   - window-boundary events: events between the end sentinel and the next start are dropped from every
#     window, except that an overflow there marks the PREVIOUS suite unreliable;
#   - `env -i`, the scratch PATH and the missing network can change what a suite reads relative to a
#     developer shell, and a suite needing installed dependencies the fresh checkout lacks fails (rc != 0,
#     therefore unreliable, never a re-promotion);
#   - hardlinked or symlink-aliased reads (census issue #8800) and the kernel's coalescing of identical
#     consecutive events (repeat opens are invisible; irrelevant to which-files evidence).
# Test-only seams: AUDIT_READS_LOADAVG_FILE (replaces /proc/loadavg), AUDIT_READS_ALLOW_NO_NETNS=1 (run
# without a network namespace when neither tool works; the header row says netns=none).

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SELF_DIR/lib/inotify-open-recorder.py"

CAP_DIRS=8
CAP_FILES=700
CAP_COVER=14
SENT_DIR=".audit-sentinels"

# Carried-disqualifier table (one entry per line: name|ERE, split at the FIRST |). Scanned over the suite
# file with whole-line comments removed. Deliberately broad: a false hit keeps a suite always-on.
_B='(^|[^[:alnum:]_./-])'
_E='([^[:alnum:]_-]|$)'
DISQ_TABLE=(
  "git-diff|${_B}git[^#]*[[:space:]]diff${_E}"
  "git-log|${_B}git[^#]*[[:space:]]log${_E}"
  "git-show|${_B}git[^#]*[[:space:]]show${_E}"
  "git-rev-list|${_B}git[^#]*[[:space:]]rev-list${_E}"
  "git-merge-base|${_B}git[^#]*[[:space:]]merge-base${_E}"
  "git-status|${_B}git[^#]*[[:space:]]status${_E}"
  "git-ls-files|${_B}git[^#]*[[:space:]]ls-files${_E}"
  "git-ls-tree|${_B}git[^#]*[[:space:]]ls-tree${_E}"
  "origin-main|origin/main"
  "changed-flag|--changed${_E}"
  "base-flag|[[:space:]]--base${_E}"
  "net-curl|${_B}(curl|wget)[[:space:]]"
  "net-gh|${_B}gh[[:space:]]+(api|pr|issue|run|repo|auth|release|workflow)${_E}"
  "net-doppler|${_B}doppler[[:space:]]"
  "net-ssh|${_B}(ssh|scp)[[:space:]]"
  "clock-date|${_B}date([[:space:]]|\$)"
  "clock-epoch|[\$]\{?(EPOCHSECONDS|EPOCHREALTIME|SECONDS)${_E}"
)

# Awk: cut the event stream into per-window files (see verdict()).
# shellcheck disable=SC2016  # awk program text: the single quotes are intentional
SEG_AWK='
BEGIN { FS = "\t"; cur = 0; gap = 0; pre = sd "/"; plen = length(pre) + length(nonce) + 1 }
function wf(k, n) { return od "/" k "." n }
{
  kind = $1; p = $2
  if (index(p, pre) == 1) {
    if (kind == "O" && substr(p, length(pre) + 1, length(nonce) + 1) == nonce "-") {
      t = substr(p, plen + 1)
      if (t ~ /^(start|end)-[0-9]+$/) {
        split(t, a, "-"); n = a[2] + 0
        if (a[1] == "start") {
          if (cur != 0) { bad[cur]++ }
          else if (n in began) { dup[n]++ }
          else {
            began[n] = 1; cur = n; gap = 0; split("", seen)
            printf "" > wf("o", n); printf "" > wf("d", n); printf "" > wf("k", n)
          }
        } else {
          if (cur == n) { fin[n] = 1; cur = 0; gap = n; close(wf("o", n)); close(wf("d", n)); close(wf("k", n)) }
          else if (n in fin) { dup[n]++ }
          else { bad[(cur != 0) ? cur : n]++ }
        }
      }
    }
    next
  }
  if (kind == "Q" && NF == 1) { if (cur) qin[cur]++; else if (gap) qgap[gap]++; next }
  if ((kind == "O" || kind == "D" || kind == "C") && NF == 2 && p != "") {
    if (!cur) next
    if (p ~ /(^|\/)__pycache__(\/|$)/) next
    key = kind SUBSEP p; if (key in seen) next
    seen[key] = 1
    print p >> wf((kind == "O") ? "o" : ((kind == "D") ? "d" : "k"), cur)
    next
  }
  if (cur) mal[cur]++; else if (gap) mal[gap]++
}
END {
  for (n in began)
    printf "%d %d %d %d %d %d %d\n", 1, (n in fin) ? 1 : 0, dup[n] + 0, bad[n] + 0, mal[n] + 0, qin[n] + 0, qgap[n] + 0 > (od "/s." n)
}'

# Awk: paths (stdin) not covered by the cover string (| separated). Directory entries end in "/".
# shellcheck disable=SC2016  # awk program text: the single quotes are intentional
UNCOVERED_AWK='
BEGIN { n = split(cover, c, "|") }
{
  p = $0; q = p; if (isdir) q = p "/"; ok = 0
  for (i = 1; i <= n; i++) {
    e = c[i]; if (e == "" || e == "-") continue
    if (e == p || e == q) { ok = 1; break }
    if (substr(e, length(e), 1) == "/" && index(q, e) == 1) { ok = 1; break }
  }
  if (!ok) print p
}'

# Awk: file-test / stat / ls / find operands of a shell or script file (whole-line comments skipped).
# shellcheck disable=SC2016  # awk program text: the single quotes are intentional
PROBE_AWK='
/^[ \t]*#/ { next }
{
  s = $0
  while (match(s, /(\[\[?|[ \t;&|(`]test|^test)[ \t]+(![ \t]+)?-[efdrwxsLhSpbcgukON][ \t]+("[^"]*"|\047[^\047]*\047|[^] \t;&|)<>]+)/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    sub(/^.*[ \t]-[efdrwxsLhSpbcgukON][ \t]+/, "", t); print t
  }
  s = $0
  while (match(s, /(^|[ \t;&|(`])(stat|ls|find)([ \t]+-[A-Za-z0-9=%]+)*[ \t]+("[^"]*"|\047[^\047]*\047|[^ \t;&|)<>-][^ \t;&|)<>]*)/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    sub(/^[ \t;&|(`]*(stat|ls|find)([ \t]+-[A-Za-z0-9=%]+)*[ \t]+/, "", t); print t
  }
}'

_CLEAN_DIRS=()
NEW_DIR=""
SUITE_PID=""
READER_PID=""

usage() {
  cat <<'USAGE'
usage: audit-suite-reads.sh record  [--rev REV] [--repo DIR] [--only LABEL[,LABEL...]] [--mode demote|check]
                                    [--cover-from-selection] [--max-load N] [--timeout S] [--reps N]
                                    [--out DIR] [--allow-unresolved-probes]
       audit-suite-reads.sh verdict --events F --reader-err F --meta F --root DIR [--mode demote|check]
                                    [--allow-unresolved-probes]
       audit-suite-reads.sh --help

record   audit the registered suites of REV (default HEAD) in a private git-archive checkout and print the
         AUDIT_READS table (also written to <out>/table.tsv).
verdict  replay a recording (events, reader stderr, meta, checkout root) through the same verdict().
--cover-from-selection  cover = anchored edges from `test-all.sh --print-selection --paths=README.md` run in
         the audited checkout (plus the suite's own files); without it only the suite's own files cover.
--only LABEL[,LABEL...]  audit these registrations.   --max-load N  refuse above this 1-minute load (default 4.0).
--mode   demote (default; demotable|uncovered|disqualified|unreliable) or check (covered|uncovered|unreliable).
exit: 0 decided, 2 usage, 3 at least one row unreliable, 4 zero suites or zero windows.
Blind spots are listed in this script's header.
USAGE
}

die_usage() { printf 'audit-suite-reads: %s\n' "$1" >&2; return 2; }

# new_tracked_dir <tag> -> NEW_DIR (0700, removed by cleanup). Sets a global: a $(...) call would register the
# directory in a subshell and the EXIT trap would never see it.
new_tracked_dir() {
  local base="${TMPDIR:-/var/tmp}" d
  d="$(umask 077 && mktemp -d "$base/soleur-audit-reads.$1.XXXXXXXX")" || return 1
  _CLEAN_DIRS[${#_CLEAN_DIRS[@]}]="$d"
  NEW_DIR="$d"
}

cleanup() {
  local d
  [[ -z "$SUITE_PID" ]] || kill -KILL -- "-$SUITE_PID" 2>/dev/null
  [[ -z "$READER_PID" ]] || kill "$READER_PID" 2>/dev/null
  for d in ${_CLEAN_DIRS[@]+"${_CLEAN_DIRS[@]}"}; do
    case "$d" in
      /*/soleur-audit-reads.*) [[ -d "$d" && ! -L "$d" ]] && rm -rf -- "$d" ;;
    esac
  done
  return 0
}
install_traps() {
  trap cleanup EXIT
  trap 'cleanup; exit 130' INT
  trap 'cleanup; exit 143' TERM
  trap 'cleanup; exit 129' HUP
}

# ---- verdict ---------------------------------------------------------------------------------------------
_v_covered() { # _v_covered <operand> <cover> : 0 iff the repo-relative probe operand lies on the cover
  local op="$1" e
  local -a es
  IFS='|' read -r -a es <<< "$2"
  for e in ${es[@]+"${es[@]}"}; do
    [[ -n "$e" && "$e" != "-" ]] || continue
    [[ "$e" == "$op" || "$e/" == "$op/" ]] && return 0
    [[ "$e" == */ && "$op/" == "$e"* ]] && return 0
    [[ "$e" == "$op"/* ]] && return 0
  done
  return 1
}

_v_window_reason() { # _v_window_reason <index> -> WR (empty when the window is trustworthy)
  local i=$1 id s_end s_dup s_bad s_mal s_qin s_qgap
  id="${W_ID[$i]}"; WR=""
  if [[ -n "$gl" ]]; then WR="$gl"; return; fi
  if [[ "${W_FLAG[$i]}" != "-" ]]; then WR="${W_FLAG[$i]}"; return; fi
  case "${W_RC[$i]}" in 0) : ;; 124) WR="timeout"; return ;; *) WR="rc"; return ;; esac
  if [[ ! -f "$vt/s.$id" ]]; then WR="sentinel"; return; fi
  read -r _ s_end s_dup s_bad s_mal s_qin s_qgap < "$vt/s.$id"
  if (( s_qin > 0 )); then WR="q_overflow"; return; fi
  if (( s_qgap > 0 )); then WR="q_overflow_gap"; return; fi
  if (( s_end == 0 || s_dup > 0 || s_bad > 0 )); then WR="sentinel"; return; fi
  if (( s_mal > 0 )); then WR="malformed"; return; fi
}

_v_row() {
  printf 'AUDIT_READS\tlabel=%s\tverdict=%s\treason=%s\trc=%s\tfiles=%s\tdirs=%s\tcover=%s\tunresolved=%s\tload=%s\trev=%s\tmode=%s\tdetail=%s\n' "$@"
}

_v_group() { # _v_group <first-window-index> <last-window-index> : one row per label
  local i=$1 j=$2 k id lbl reason="" rcg=0 verdict reason_out detail=""
  local nfiles=0 ndirs=0 ncover=0 ncreated=0 unres=0 nunc=0 f flagged="" info="" operand
  local -a sfs es unc
  lbl="${W_LABEL[$i]}"; id="${W_ID[$i]}"
  for ((k = i; k <= j; k++)); do
    _v_window_reason "$k"
    [[ -z "$reason" ]] && reason="$WR"
    if [[ "${W_RC[$k]}" != "0" && "${W_RC[$k]}" != "-" && "$rcg" == "0" ]]; then rcg="${W_RC[$k]}"; fi
  done
  if [[ -z "$reason" && "$j" -gt "$i" ]]; then
    for ((k = i; k <= j; k++)); do
      { sed 's/^/O /' "$vt/o.${W_ID[$k]}"; sed 's/^/D /' "$vt/d.${W_ID[$k]}"; } | LC_ALL=C sort -u > "$vt/set.${W_ID[$k]}"
    done
    for ((k = i + 1; k <= j; k++)); do
      cmp -s "$vt/set.$id" "$vt/set.${W_ID[$k]}" || { reason="repeat_disagree"; break; }
    done
  fi
  if [[ -n "$reason" ]]; then
    ANY_UNRELIABLE=1
    detail="win:${W_ID[$i]}"
    [[ "${W_RC[$i]}" == "-" ]] && rcg="-"
    _v_row "$lbl" unreliable "$reason" "$rcg" - - - - "${W_LOAD[$i]}" "$rev" "$mode" "$detail"
    return
  fi
  # ---- decided: facts from the first window (all windows agree on the opened set) ----
  nfiles=$(( $(wc -l < "$vt/o.$id") ))
  ndirs=$(awk -F/ '{ k = (NF >= 2) ? $1 "/" $2 : $1; s[k] = 1 } END { n = 0; for (k in s) n++; print n }' "$vt/o.$id")
  if [[ "${W_COVER[$i]}" != "-" ]]; then IFS='|' read -r -a es <<< "${W_COVER[$i]}"; ncover=${#es[@]}; fi
  for ((k = i; k <= j; k++)); do ncreated=$(( ncreated + $(wc -l < "$vt/k.${W_ID[$k]}") )); done
  { awk -v cover="${W_COVER[$i]}" -v isdir=0 "$UNCOVERED_AWK" "$vt/o.$id"; awk -v cover="${W_COVER[$i]}" -v isdir=1 "$UNCOVERED_AWK" "$vt/d.$id"; } > "$vt/unc.$id"
  nunc=$(( $(wc -l < "$vt/unc.$id") ))
  # static scan of the suite files: probes outside the cover, unresolved probe operands, regex table
  : > "$vt/scan.$id"; local nscanned=0
  if [[ "${W_FILES[$i]}" != "-" ]]; then
    IFS='|' read -r -a sfs <<< "${W_FILES[$i]}"
    for f in ${sfs[@]+"${sfs[@]}"}; do
      [[ -f "$root/$f" ]] || continue
      nscanned=$((nscanned + 1))
      grep -v '^[[:space:]]*#' "$root/$f" >> "$vt/scan.$id" || true
      while IFS= read -r operand; do
        operand="${operand#\"}"; operand="${operand%\"}"; operand="${operand#\'}"; operand="${operand%\'}"
        [[ -n "$operand" ]] || continue
        case "$operand" in
          *'$'*|*'`'*|*'*'*|*'?'*|*'{'*|*'~'*) unres=$((unres + 1)) ; continue ;;
          /*) continue ;;
        esac
        operand="${operand#./}"; operand="${operand%/}"
        _v_covered "$operand" "${W_COVER[$i]}" || flagged="$flagged;probe:$operand"
      done < <(awk "$PROBE_AWK" "$root/$f")
    done
  fi
  local entry name re
  for entry in "${DISQ_TABLE[@]}"; do
    name="${entry%%|*}"; re="${entry#*|}"
    if grep -qE -e "$re" "$vt/scan.$id"; then flagged="$flagged;regex:$name"; fi
  done
  (( ncreated > 0 )) && flagged="$flagged;created-dir"
  (( nscanned == 0 )) && flagged="$flagged;no-suite-file"
  if (( unres > 0 )) && [[ "$ALLOW_UNRES" != 1 ]]; then flagged="$flagged;unresolved-probe"; fi
  (( ndirs > CAP_DIRS || nfiles > CAP_FILES )) && info="$info;broad"
  (( ncover > CAP_COVER )) && info="$info;wide-cover"
  unc=(); while IFS= read -r f; do unc[${#unc[@]}]="$f"; done < <(head -n 8 "$vt/unc.$id")
  local unclist="" u
  for u in ${unc[@]+"${unc[@]}"}; do unclist="$unclist,$u"; done
  unclist="${unclist#,}"; (( nunc > 8 )) && unclist="$unclist,...+$((nunc - 8))"
  if [[ "$mode" == "check" ]]; then
    if (( nunc > 0 )); then verdict=uncovered; reason_out="reads-outside-cover"; else verdict=covered; reason_out=ok; fi
    detail="${unclist:+$unclist}"; local extra="${flagged}${info}"; detail="${detail}${extra:+;info${extra}}"
  else
    local all="${flagged}${info}"
    if [[ -n "$all" ]]; then
      verdict=disqualified; all="${all#;}"; reason_out="${all%%[:;]*}"; detail="$all"
    elif (( nunc > 0 )); then
      verdict=uncovered; reason_out="reads-outside-cover"; detail="$unclist"
    else
      verdict=demotable; reason_out=ok; detail=""
    fi
  fi
  _v_row "$lbl" "$verdict" "$reason_out" "$rcg" "$nfiles" "$ndirs" "$ncover" "$unres" "${W_LOAD[$i]}" "$rev" "$mode" "$detail"
}

# verdict <events> <reader-stderr> <meta> <root> <mode> <allow-unresolved 0|1>  -> rows on stdout
# returns 0 decided / 3 any unreliable / 4 zero suites or zero windows. THE ONLY function that classifies.
verdict() {
  local ev="$1" rerr="$2" meta="$3" root="$4" mode="$5" ALLOW_UNRES="${6:-0}"
  local vt nonce="" rev="-" n=0 i j lbl gl="" tag a b d e f g h nsent=0 nflag=0 ANY_UNRELIABLE=0 WR=""
  local -a W_ID W_LABEL W_RC W_FLAG W_LOAD W_COVER W_FILES
  new_tracked_dir v || return 2; vt="$NEW_DIR"
  while IFS=$'\t' read -r tag a b _ d e f g h; do
    case "$tag" in
      NONCE) nonce="$a" ;;
      REV) rev="$a" ;;
      W) W_ID[n]="$a"; W_LABEL[n]="$b"; W_RC[n]="$d"; W_FLAG[n]="$e"; W_LOAD[n]="$f"
         W_COVER[n]="$g"; W_FILES[n]="$h"; n=$((n + 1)) ;;
    esac
  done < "$meta"
  if (( n == 0 )); then printf 'audit-suite-reads: zero suites enumerated (nothing to audit)\n' >&2; return 4; fi
  [[ -n "$nonce" ]] || { printf 'audit-suite-reads: meta carries no NONCE line\n' >&2; return 2; }
  awk -v nonce="$nonce" -v od="$vt" -v sd="$SENT_DIR" "$SEG_AWK" "$ev"
  for ((i = 0; i < n; i++)); do
    [[ -f "$vt/s.${W_ID[$i]}" ]] && nsent=$((nsent + 1))
    [[ "${W_FLAG[$i]}" != "-" ]] && nflag=$((nflag + 1))
    for e in o d k; do [[ -f "$vt/$e.${W_ID[$i]}" ]] || : > "$vt/$e.${W_ID[$i]}"; done
  done
  if (( nsent == 0 && nflag == 0 )); then printf 'audit-suite-reads: zero windows recorded (no sentinel pair in the event stream)\n' >&2; return 4; fi
  grep -qx 'ready' "$rerr" || gl="reader_not_ready"
  if grep -q '^Failed to watch' "$rerr"; then gl="watch_failed"; fi
  i=0
  while (( i < n )); do
    j=$i; lbl="${W_LABEL[$i]}"
    while (( j + 1 < n )) && [[ "${W_LABEL[$((j + 1))]}" == "$lbl" ]]; do j=$((j + 1)); done
    _v_group "$i" "$j"
    i=$((j + 1))
  done
  (( ANY_UNRELIABLE == 0 )) || return 3
  return 0
}

# ---- record ------------------------------------------------------------------------------------------------
loadavg() { awk '{ print $1; exit }' "${AUDIT_READS_LOADAVG_FILE:-/proc/loadavg}" 2>/dev/null; }

sweep_stale() { # remove prefixed directories older than a day under the mktemp root
  local base="${TMPDIR:-/var/tmp}" d
  [[ -n "$base" && "$base" != "/" && -d "$base" ]] || return 0
  for d in "$base"/soleur-audit-reads.*; do
    [[ -d "$d" && ! -L "$d" && "$d" == "$base"/soleur-audit-reads.* ]] || continue
    [[ -n "$(find "$d" -maxdepth 0 -mmin +1440 2>/dev/null)" ]] || continue
    rm -rf -- "$d"
  done
}

make_scratch_bin() { # make_scratch_bin <dir> : symlinks of the resolved tools a suite may need = the ENTIRE PATH
  local bin="$1" t p
  mkdir -p "$bin"
  for t in bash sh git python3 node bun cat cp mv rm mkdir rmdir ls ln chmod touch date sleep head tail wc sort uniq \
           tr cut tee sed awk grep egrep fgrep find xargs env dirname basename readlink realpath mktemp diff cmp \
           tar gzip gunzip id uname hostname printf test true false expr seq stat timeout tput comm paste od \
           sha256sum md5sum cksum nl rev yes kill pgrep pkill ps flock df nproc free uptime getconf sha1sum base64 jq lscpu perl truncate setsid stdbuf install mkfifo nohup pstree lsof fuser; do
    # type -P, never command -v: an interactive shell may define grep (or another tool) as a FUNCTION
    # (agent shells shim grep), and command -v then prints the bare name, which is not an absolute path,
    # so the tool silently never reaches the scratch PATH and the suites fail with "command not found".
    p="$(type -P "$t" 2>/dev/null)" || continue
    [[ "$p" == /* && -x "$p" ]] && ln -sf "$p" "$bin/$t"
  done
}

cmd_record() {
  local repo="" rev="HEAD" only="" mode="demote" cover_sel=0 maxload="4.0" tmo=600 reps=2 outdir="" allow_unres=0
  while (( $# > 0 )); do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;; --rev) rev="${2:-}"; shift 2 ;; --only) only="${2:-}"; shift 2 ;;
      --mode) mode="${2:-}"; shift 2 ;; --cover-from-selection) cover_sel=1; shift ;;
      --max-load) maxload="${2:-}"; shift 2 ;; --timeout) tmo="${2:-}"; shift 2 ;; --reps) reps="${2:-}"; shift 2 ;;
      --out) outdir="${2:-}"; shift 2 ;; --allow-unresolved-probes) allow_unres=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die_usage "unknown record option: $1"; return 2 ;;
    esac
  done
  case "$mode" in demote|check) : ;; *) die_usage "--mode must be demote or check"; return 2 ;; esac
  [[ "$maxload" =~ ^[0-9]+([.][0-9]+)?$ ]] || { die_usage "--max-load needs a non-negative number"; return 2; }
  [[ "$tmo" =~ ^[0-9]+$ && "$tmo" -ge 1 ]] || { die_usage "--timeout needs a positive integer"; return 2; }
  [[ "$reps" =~ ^[1-9]$ ]] || { die_usage "--reps needs 1..9"; return 2; }
  case "$only" in *..*|*$'\t'*|*$'\n'*) die_usage "--only must not contain .. or control characters"; return 2 ;; esac
  [[ "$(uname -s)" == "Linux" ]] || { die_usage "Linux only (raw inotify)"; return 2; }
  python3 -c 'import ctypes; ctypes.CDLL(None).inotify_init1' >/dev/null 2>&1 \
    || { die_usage "python3 with ctypes inotify support is required"; return 2; }
  local -a NETWRAP=(); local netns="unshare"
  if unshare -rn true >/dev/null 2>&1; then NETWRAP=(unshare -rn)
  elif bwrap --unshare-net --dev-bind / / true >/dev/null 2>&1; then NETWRAP=(bwrap --unshare-net --dev-bind / /); netns="bwrap"
  elif [[ "${AUDIT_READS_ALLOW_NO_NETNS:-}" == "1" ]]; then netns="none"
  else die_usage "refusing to start: no network-less namespace tool (unshare -rn / bwrap --unshare-net) works here"; return 2
  fi
  [[ -n "$repo" ]] || repo="$(git -C "$SELF_DIR/.." rev-parse --show-toplevel)" || { die_usage "not inside a git repository"; return 2; }
  local sha
  sha="$(git -C "$repo" rev-parse --verify "$rev^{commit}" 2>/dev/null)" || { die_usage "cannot resolve revision: $rev"; return 2; }
  if ! git -C "$repo" merge-base --is-ancestor "$sha" HEAD 2>/dev/null \
     && ! git -C "$repo" merge-base --is-ancestor "$sha" origin/main 2>/dev/null; then
    die_usage "revision $sha is an ancestor of neither HEAD nor origin/main"; return 2
  fi
  install_traps
  sweep_stale
  local run co S out meta ev rerr nonce i w rep
  new_tracked_dir run || return 2; run="$NEW_DIR"
  co="$run/co"; S="$run/scratch"; mkdir -p "$co" "$S/home" "$S/tmp" "$S/xdg-config" "$S/xdg-cache" "$S/xdg-data" "$S/sb"
  if [[ -n "$outdir" ]]; then mkdir -p "$outdir" && chmod 700 "$outdir"; out="$outdir"; else out="$(umask 077 && mktemp -d "${TMPDIR:-/var/tmp}/soleur-audit-reads-out.XXXXXXXX")"; fi
  mkdir -p "$out/logs"; meta="$out/meta"; ev="$out/events"; rerr="$out/reader.err"; : > "$ev"; : > "$rerr"
  make_scratch_bin "$S/bin"
  printf '[user]\n\tname = audit\n\temail = audit@invalid\n[commit]\n\tgpgsign = false\n' > "$S/home/.gitconfig"
  git -C "$repo" archive --format=tar "$sha" | tar -x -C "$co"
  local arch_rc=("${PIPESTATUS[@]}")
  [[ "${arch_rc[0]}" == 0 && "${arch_rc[1]}" == 0 ]] || { die_usage "git archive/extract of $sha failed"; return 2; }
  local G=(env -i HOME="$S/home" PATH="$(dirname "$(command -v git)"):$PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$co"
           -c user.name=audit -c user.email=audit@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null)
  if ! { "${G[@]}" init -q --template= && "${G[@]}" add -A >/dev/null 2>&1 && "${G[@]}" commit -q -m "audit $sha" >/dev/null 2>&1; }; then
    die_usage "could not initialise the private checkout"; return 2
  fi
  nonce="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  local -a RUNENV=(env -i "HOME=$S/home" "TMPDIR=$S/tmp" "XDG_CONFIG_HOME=$S/xdg-config" "XDG_CACHE_HOME=$S/xdg-cache"
                   "XDG_DATA_HOME=$S/xdg-data" "SOLEUR_SCRATCH_BASE=$S/sb" "PATH=$S/bin" LANG=C TERM=dumb
                   PYTHONDONTWRITEBYTECODE=1 GIT_CONFIG_NOSYSTEM=1)
  # enumerate + selection inside the same checkout and environment
  local enum sel
  enum="$(cd "$co" && "${NETWRAP[@]+"${NETWRAP[@]}"}" "${RUNENV[@]}" bash scripts/test-all.sh --enumerate-commands all 2>"$out/enum.err")" || true
  sel=""
  if (( cover_sel == 1 )); then
    sel="$(cd "$co" && "${NETWRAP[@]+"${NETWRAP[@]}"}" "${RUNENV[@]}" bash scripts/test-all.sh --print-selection --paths=README.md 2>"$out/sel.err")" || true
    printf '%s\n' "$sel" > "$out/selection.tsv"
  fi
  local -a LABELS=() ARGV_LINES=()
  local line lbl
  while IFS= read -r line; do
    [[ "$line" == SUITE_COMMAND$'\t'* ]] || continue
    lbl="$(printf '%s' "$line" | cut -f2)"
    # --only takes one label or a comma-separated list (labels contain no comma): one extraction and one
    # cover derivation then serves a whole audit instead of one per label.
    [[ -z "$only" || ",$only," == *",$lbl,"* ]] || continue
    LABELS[${#LABELS[@]}]="$lbl"; ARGV_LINES[${#ARGV_LINES[@]}]="$line"
  done <<EOF
$enum
EOF
  printf 'NONCE\t%s\nREV\t%s\n' "$nonce" "$sha" > "$meta"
  local total=$(( ${#LABELS[@]} * reps ))
  mkdir -p "$co/$SENT_DIR"
  for ((i = 1; i <= total; i++)); do : > "$co/$SENT_DIR/$nonce-start-$i"; : > "$co/$SENT_DIR/$nonce-end-$i"; done
  "${G[@]}" status --porcelain --ignored >/dev/null 2>&1   # prime git's index stat cache outside any window
  if (( ${#LABELS[@]} > 0 )); then
    python3 "$READER" "$co" --exclude .git --exclude node_modules >"$ev" 2>"$rerr" &
    READER_PID=$!
    for i in $(seq 1 600); do grep -qx 'ready' "$rerr" && break; kill -0 "$READER_PID" 2>/dev/null || break; sleep 0.1; done
  fi
  w=0
  local -a argv fields
  local x f rc flag load cover files edges a code_files cover_files started
  for ((i = 0; i < ${#LABELS[@]}; i++)); do
    lbl="${LABELS[$i]}"
    IFS=$'\t' read -r -a fields <<< "${ARGV_LINES[$i]}"
    argv=("${fields[@]:2}")
    cover_files=""; code_files=""
    for a in ${argv[@]+"${argv[@]}"}; do
      x="${a#./}"
      case "$x" in /*|*..*|"") continue ;; esac
      if [[ -f "$co/$x" ]]; then
        cover_files="$cover_files|$x"
        case "$x" in *.sh|*.bash|*.py|*.mjs|*.js|*.cjs|*.ts) code_files="$code_files|$x" ;; esac
      elif [[ -d "$co/$x" ]]; then cover_files="$cover_files|${x%/}/"; fi
    done
    edges=""
    if (( cover_sel == 1 )); then
      edges="$(printf '%s\n' "$sel" | awk -F'\t' -v l="$lbl" '$1 == "AFFECTED_SELECTED" && $2 == l { print $5; exit }' | tr '|' '\n' | sed -e 's/^\^//' -e 's#^\./##' | grep -v '^$' | tr '\n' '|')"
    fi
    cover="${edges}${cover_files#|}"; cover="${cover%|}"; [[ -n "$cover" ]] || cover="-"
    files="${code_files#|}"; [[ -n "$files" ]] || files="-"
    for ((rep = 1; rep <= reps; rep++)); do
      w=$((w + 1)); rc="-"; flag="-"; load="$(loadavg)"; [[ -n "$load" ]] || load="0"
      if awk -v l="$load" -v m="$maxload" 'BEGIN { exit !(l + 0 > m + 0) }'; then
        flag="load_refused"
      else
        : < "$co/$SENT_DIR/$nonce-start-$w"
        ( cd "$co" && exec setsid timeout --kill-after=3 "$tmo" "${NETWRAP[@]+"${NETWRAP[@]}"}" "${RUNENV[@]}" "${argv[@]}" ) >"$out/logs/$w.log" 2>&1 </dev/null &
        SUITE_PID=$!
        wait "$SUITE_PID"; rc=$?
        kill -KILL -- "-$SUITE_PID" 2>/dev/null
        SUITE_PID=""
        : < "$co/$SENT_DIR/$nonce-end-$w"
        started=0
        for t in $(seq 1 200); do
          if grep -qxF -- "O"$'\t'"$SENT_DIR/$nonce-end-$w" "$ev"; then started=1; break; fi
          kill -0 "$READER_PID" 2>/dev/null || { flag="reader_dead"; break; }
          sleep 0.05
        done
        [[ "$started" == 1 || "$flag" != "-" ]] || flag="sentinel_timeout"
        if [[ -n "$("${G[@]}" status --porcelain --ignored 2>/dev/null | grep -v -e "^?? $SENT_DIR/\$" -e "^!! $SENT_DIR/\$" || true)" ]]; then
          [[ "$flag" != "-" ]] || flag="contaminated"
          "${G[@]}" clean -fdxq -e "$SENT_DIR" >/dev/null 2>&1; "${G[@]}" checkout -q -- . >/dev/null 2>&1
        fi
      fi
      printf 'W\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$w" "$lbl" "$rep" "$rc" "$flag" "$load" "$cover" "$files" >> "$meta"
      printf '[audit] %s rep=%s rc=%s flag=%s\n' "$lbl" "$rep" "$rc" "$flag" >&2
      # a faulty first recording is retried by the operator, not repeated here
      if [[ "$flag" != "-" || ( "$rc" != "0" && "$rc" != "-" ) ]]; then break; fi
    done
  done
  if [[ -n "$READER_PID" ]]; then kill "$READER_PID" 2>/dev/null; wait "$READER_PID" 2>/dev/null; READER_PID=""; fi
  local vrc
  printf 'AUDIT_READS_HEADER\trev=%s\tmode=%s\tnetns=%s\tmax_load=%s\tout=%s\n' "$sha" "$mode" "$netns" "$maxload" "$out" > "$out/table.tsv"
  verdict "$ev" "$rerr" "$meta" "$co" "$mode" "$allow_unres" >> "$out/table.tsv"   # RECORD-VERDICT-CALL
  vrc=$?
  cat "$out/table.tsv"
  return "$vrc"
}

cmd_verdict() {
  local events="" rerr="" meta="" root="" mode="demote" allow_unres=0
  while (( $# > 0 )); do
    case "$1" in
      --events) events="${2:-}"; shift 2 ;; --reader-err) rerr="${2:-}"; shift 2 ;; --meta) meta="${2:-}"; shift 2 ;;
      --root) root="${2:-}"; shift 2 ;; --mode) mode="${2:-}"; shift 2 ;; --allow-unresolved-probes) allow_unres=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die_usage "unknown verdict option: $1"; return 2 ;;
    esac
  done
  case "$mode" in demote|check) : ;; *) die_usage "--mode must be demote or check"; return 2 ;; esac
  [[ -f "$events" && -f "$rerr" && -f "$meta" && -d "$root" ]] \
    || { die_usage "verdict needs --events F --reader-err F --meta F --root DIR (usage: see --help)"; return 2; }
  install_traps
  verdict "$events" "$rerr" "$meta" "$root" "$mode" "$allow_unres"
}

main() {
  case "${1:-}" in
    -h|--help|help) usage; return 0 ;;
    record) shift; cmd_record "$@" ;;
    verdict) shift; cmd_verdict "$@" ;;
    "") usage >&2; return 2 ;;
    *) die_usage "unknown subcommand: $1 (usage: see --help)"; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
