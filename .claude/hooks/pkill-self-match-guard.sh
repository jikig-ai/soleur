#!/usr/bin/env bash
# PreToolUse hook on Bash.
# Blocks two spellings of one defect — a process scan whose corpus includes the
# scanner's own text:
#   1. `pkill -f <pat>` / `pgrep -f <pat>` — signal-sending. UNCONDITIONAL.
#   2. `ps <args-showing> | grep/egrep/fgrep/awk <pat>` — read-only (#8330).
#      Denied only when <pat>, run as the regex that stage will run, matches
#      the wrapper line `bash -c <the whole command>`. Simulated, not guessed.
#
# Source class: "a scan whose corpus includes the scanner's own text."
# `pkill -f` matches an unanchored regex against the WHOLE JOINED command line of
# every process, and the invoking shell, its wrappers, and any sibling watcher
# spawned as `bash -c '…<pat>…'` all carry <pat> in their argv. pkill excludes
# only its OWN pid — not its parent, not its siblings.
#
# Why a hook and not another learning: this class is documented in ~31 learning
# files across four months, in work/SKILL.md and git-worktree/SKILL.md, and the
# sanctioned replacement already ships as plugins/soleur/scripts/lib/proc.sh
# (list_runs / kill_mine, which resolve ownership via /proc/<pid>/cwd and exclude
# self + ancestry). It kept recurring because the command is typed from memory.
# Prose has had four months and ~31 attempts; this is the mechanical gate.
# Measured on PR #7888: the narrowing `pkill -f '^bash .*<script>\.sh'` does NOT
# fix it — `^` anchors at the start of the joined cmdline, not an argv slot, so a
# `bash -c '…<script>.sh…'` watcher still matches.
#
# Detection (arm 1):
#   tool_name == Bash
#   AND the command uses `pkill -f` or `pgrep -f`
#
# UNCONDITIONAL for `-f`, and that is the point. The Bash tool runs each command
# as `bash -c '<the whole command>'`, so the invoking wrapper's OWN argv contains
# the pattern by construction — verified from this session's `ps` output. `-f`
# matches against the full command line of every process, and pkill/pgrep exclude
# only their own pid, never the parent. So a `-f` pattern ALWAYS matches at least
# the shell that issued it, plus any sibling watcher carrying it. There is no
# "safe" pattern to allow-list, which is why an "appears elsewhere in the command"
# heuristic (the first draft of this hook) missed the literal incident case:
#   until ! pgrep -f "run-registered-suites"; do sleep 5; done
# where the pattern appears ONLY inside the pgrep invocation and the collision is
# with the wrapper.
#
# Escape hatches that remain open, so this is a redirect and not a wall:
#   * `pgrep`/`pkill` WITHOUT `-f` match the process NAME only — no self-match.
#   * a PID captured at spawn (`cmd & pid=$!`) names the process exactly.
#   * proc.sh list_runs / kill_mine resolve ownership via /proc/<pid>/cwd.
#
# ---------------------------------------------------------------------------
# Detection (arm 2, read-only — #8330):
#   the -f arm did not fire
#   AND an args-showing `ps` stage sits at a command boundary and is piped
#   AND its grep/egrep/fgrep/awk regex stage(s), run against the wrapper model,
#       leave the wrapper line alive.
#
# The wrapper, measured from inside the Bash tool on 2026-09-19 with
# `ps -o args= -p $$` (re-run that to re-verify; it is the premise):
#   /usr/bin/bash -c source <snapshot>.sh 2>/dev/null || true && … && eval '<cmd>' < /dev/null && pwd -P >| …
# So `ps -eo args | grep -c '<pat>'` scans a line carrying the WHOLE command,
# including <pat> itself. Measured on this host, each spelling alone in a Bash
# tool call (`zzqq-marker.sh` is a literal no process carries):
#   grep -c 'zzqq-marker.sh'     (unescaped dot)  → 3   the regex matches its own literal
#   grep -c 'zzqq-marker\.sh'    (escaped dot)    → 0   the wrapper carries `\.`, the regex needs `.`
#   grep -c '[t]est-all\.sh' with scripts/test-all.sh mentioned elsewhere → ≥1
#   awk '$1=="bash" && $2=="scripts/test-all.sh"' | wc -l            → the runner only
# The incident (#8231, the 2026-09-18 learning "every instrument I waited on was
# counting itself"): two wait-for-quiet watchers built as `ps -eo args | grep -c`
# never fired across ~1h05m and ~25m, each reporting "still waiting" — the same
# status a busy host reports. A third, anchored on an argv SLOT, fired within
# seconds. So "the pattern appears elsewhere in the command" is NOT the property
# (row 1 above self-matches with no other mention); the property is "the regex
# matches the wrapper line", and that is computable here with one grep per stage.
#
# Simulation rule. MODEL = `bash -c <raw command>` (newlines preserved — `ps`
# prints the wrapper's argv newlines verbatim, so a multi-line command is several
# lines and `^` anchors on each; grep over a herestring reproduces that). For each
# args-showing, self-listing `ps` stage in SCAN = strip_heredocs(<command>), walk
# the `|`-separated stages that follow until the pipeline ends (`;` `&&` `||` `&`
# `)` newline) or a stage that is not grep/egrep/fgrep/awk. Each matcher stage's
# pattern is run against MODEL with its own flavour (-G/-E/-F, -i/-w/-x): a
# non-`-v` stage that matches keeps the wrapper alive; a `-v` stage that matches,
# or a non-`-v` stage that does not, FILTERS the wrapper and the pipeline is safe.
# `grep -v grep` therefore filters (the wrapper carries "grep" by construction),
# which is why the work/SKILL.md liveness triple `ps -ef | grep -E x | grep -v grep`
# stays allowed. Verdicts OR-accumulate across pipelines: one alive pipeline denies.
#
# Trigger, stage walk and pattern extraction read SCAN; only MODEL reads the raw
# command. Heredoc BODIES are prose being written (a learning, a skill file, this
# header) and must not trigger — the #7994 interaction. They stay IN the model
# because the wrapper carries them: a heredoc mentioning scripts/test-all.sh
# re-arms a bracket-tricked poller in the same command.
#
# `ps` is args-showing when a bare BSD token carries a/x/u (`aux`, `ax`, `x`), a
# dashed BSD bundle of a/u/x/w carries x (`-aux`, `-ax`), a Unix bundle carries
# f/F (`-ef`, `-F`), or -o/-O/--format names args|cmd|command. `comm`-only,
# bare `-e`, `-l` are name-only (no self-match, like pgrep without -f). A ps
# restricted to named pids (-p/--pid/-q/--quick-pid) is exempt — the one ps
# that cannot list the wrapper. `-C bash` is NOT a pid restriction (the
# wrapper's comm is bash); `-u`/`-t`/`-s` can all list it.
#
# Fail-open, PER PIPELINE (`continue`, never `exit`): a literal holding `$`, a
# backtick or a quote; an empty literal; `-f FILE`; `-P`; an unterminated quote
# (a `|` inside a quoted pattern splits the stage there and lands here); the
# simulation grep returning anything but 0/1 (2 = invalid regex, 124 = the 2 s
# timeout, 127 = no binary). A later pipeline in the same command still gets its
# verdict. A missing lib/incidents.sh skips the whole arm with a stderr WARN —
# fail-OPEN, not an identity shim (a shim would over-detect exactly when the
# environment is degraded, denying a doc-writing heredoc).
#
# Accepted gaps (name the row when you close one; do not widen silently):
#   * pattern in a variable, `-f FILE`, `-P`, a second `-e` (only the first is
#     tested), a `\`-newline-continued stage, a `sudo`/`command`/`/bin/`-prefixed
#     `ps`, `-o` with an attached value (`-oargs`), a long flag taking a separate
#     argument before the pattern (`--max-count 1`).
#   * a pipeline inside a quoted string (`timeout 30 bash -c '…ps…'`, `watch`,
#     `nohup bash -c '…'`) or inside an EXECUTED heredoc (`bash <<'EOF'`) — the
#     body is stripped from the trigger scan by design (suite row A17).
#   * `ps … > file; grep pat file` — not a pipeline.
#   * a `;`/`&`/`(` boundary inside a quoted string denies (the boundary regex
#     does not track quotes) — an accepted FALSE DENY, suite row D19; the reason
#     is self-explaining.
#   * the model is prefix-free: a pattern matching only the real wrapper's
#     snapshot preamble or grep-rewrite.sh prefix (`grep -c command`,
#     `grep -c source`) self-matches in reality but not here (a false allow);
#     the real argv[0] is /usr/bin/bash, so `-v '^bash -c'` filters the model
#     but not the real line; the real wrapper embeds the command through
#     `eval '…'`, so a single quote inside it is rewritten `'"'"'` in argv (a
#     literal containing a quote is a fail-open arm anyway).
#   * a Monitor tool command is not a Bash tool call (work/SKILL.md records it).
#
# Idioms new to this hook set, named so the next reader does not "fix" them:
# the stage walk is a `while [[ "$rest" =~ … ]]; do …; rest="${rest#*"$m"}"; done`
# consumption loop (siblings iterate `grep -o | while read`), and every optional
# regex group is read as `${BASH_REMATCH[n]-}` so a non-participating group
# cannot abort the hook under `set -u`.
#
# Telemetry: the read-only arm emits rule id `pkill-self-match-guard-readonly`
# through lib/incidents.sh (fail-soft); the -f arm emits none — its behaviour
# and reason text are unchanged by #8330 (suite pins the single envelope, D11).
#
# Fail-open by construction: any parse failure exits 0 with no decision.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Canonical kind map (#8205): Devin wire names → Claude kinds. Absent lib
# degrades to passthrough, preserving this hook's fail-open invariant.
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook-tool-kind.sh" 2>/dev/null || true
if ! type hook_tool_kind >/dev/null 2>&1; then
  hook_tool_kind() { printf '%s\n' "${1-}"; }
  echo "WARN: hook-tool-kind.sh missing — kind gates degrade to raw-name passthrough (silent-off under Devin)" >&2
fi

# strip_heredocs + emit_incident (#8330 arm). Fail-soft: the arm checks for the
# function it needs and skips itself with a WARN when the lib is absent.
. "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
TOOL="$(hook_tool_kind "$TOOL")"
[[ "$TOOL" == "Bash" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$CMD" ]] && exit 0

# ---------------------------------------------------------------------------
# Arm 2 helpers (read-only ps pipeline). Defined before the -f arm so the -f
# arm's negative path can call readonly_arm; the -f arm's own text below is
# byte-identical to its pre-#8330 form (plan AC6 diffs the reason string).
# ---------------------------------------------------------------------------
NL=$'\n'
# A `ps` token at a command boundary: start of text, `|`, `;`, `&`, `(` (covers
# `$(`), or a newline. Never `^` alone (constitution) — the boundary set is
# what keeps `grep -n "ps aux …" README.md` (row A12) out of the trigger.
RE_PS="(^|[|;&(]|${NL})[[:space:]]*ps([[:space:]]|\|)"
# The first awk regex literal at a regex POSITION (start, whitespace, ~, !, (,
# &, |, ;, {, ,) — not the `/` inside a string like "scripts/test-all.sh".
RE_AWK='(^|[[:space:]~!(&|;{,])/([^/]+)/'

S_PAT=""; S_FLAV=G; S_INV=0; S_CI=0; S_W=0; S_X=0

# $1 = the ps stage's flag text. 0 = args-showing (full command line visible).
ps_args_showing() {
  local -a toks; read -ra toks <<<"$1"
  local tok fmt=0
  for tok in "${toks[@]}"; do
    if (( fmt )); then
      fmt=0
      [[ "$tok" =~ (^|,)(args|cmd|command)(=|,|$) ]] && return 0
      continue
    fi
    case "$tok" in
      --format=*) [[ "${tok#--format=}" =~ (^|,)(args|cmd|command)(=|,|$) ]] && return 0 ;;
      --format)   fmt=1 ;;
      --*)        : ;;
      -*)
        local letters="${tok#-}"
        [[ "$letters" =~ ^[a-zA-Z]*[fF] ]] && return 0        # Unix -f / -F / -ef
        [[ "$letters" =~ ^[auxw]+$ && "$letters" == *x* ]] && return 0   # dashed BSD -aux/-ax
        [[ "$letters" =~ ^[a-zA-Z]*[oO]$ ]] && fmt=1           # -o / -O / -eo: next token is the format
        ;;
      *)
        [[ "$tok" =~ ^[a-zA-Z]+$ && "$tok" == *[axu]* ]] && return 0   # BSD aux / ax / x / u
        ;;
    esac
  done
  return 1
}

# $1 = the ps stage's flag text. 0 = restricted to named pids (cannot list the wrapper).
ps_pid_restricted() {
  local -a toks; read -ra toks <<<"$1"
  local tok
  for tok in "${toks[@]}"; do
    case "$tok" in
      --pid|--pid=*|--ppid|--ppid=*|--quick-pid|--quick-pid=*) return 0 ;;
      --*) : ;;
      -*) [[ "${tok#-}" =~ ^[a-zA-Z]*[pq] ]] && return 0 ;;
    esac
  done
  return 1
}

# Consume one shell-ish token from $S into $TOK; $Q=1 when it was quoted.
# Returns 1 on an unterminated quote (the fail-open arm for `|` inside a pattern).
S=""; TOK=""; Q=0
next_tok() {
  S="${S#"${S%%[![:space:]]*}"}"
  [[ -z "$S" ]] && return 2
  local r
  case "$S" in
    "'"*) r="${S#\'}"; [[ "$r" == *"'"* ]] || return 1; TOK="${r%%\'*}"; S="${r#*\'}"; Q=1 ;;
    '"'*) r="${S#\"}"; [[ "$r" == *'"'* ]] || return 1; TOK="${r%%\"*}"; S="${r#*\"}"; Q=1 ;;
    *)    TOK="${S%%[[:space:]]*}"; S="${S#"$TOK"}"; Q=0 ;;
  esac
  return 0
}

# $1 = grep|egrep|fgrep, $2 = the stage text after the command word.
# 0 = S_* set; 1 = fail-open (unresolvable literal).
sim_grep() {
  local word="$1" pending=0 skip=0 dd=0 have=0 letters last
  S="$2"; S_PAT=""; S_FLAV=G; S_INV=0; S_CI=0; S_W=0; S_X=0
  case "$word" in egrep) S_FLAV=E ;; fgrep) S_FLAV=F ;; esac
  while :; do
    next_tok; local rc=$?
    (( rc == 2 )) && break
    (( rc == 1 )) && return 1
    if (( pending )); then S_PAT="$TOK"; have=1; break; fi
    if (( skip )); then skip=0; continue; fi
    if (( dd == 0 )) && (( Q == 0 )) && [[ "$TOK" == -* ]]; then
      case "$TOK" in
        --)                       dd=1 ;;
        -e|--regexp)              pending=1 ;;
        --regexp=*)               S_PAT="${TOK#--regexp=}"; have=1; break ;;
        -f|--file|--file=*|-P|--perl-regexp) return 1 ;;
        --extended-regexp)        S_FLAV=E ;;
        --fixed-strings)          S_FLAV=F ;;
        --basic-regexp)           S_FLAV=G ;;
        --ignore-case)            S_CI=1 ;;
        --invert-match)           S_INV=1 ;;
        --word-regexp)            S_W=1 ;;
        --line-regexp)            S_X=1 ;;
        --*)                      : ;;
        -*)
          letters="${TOK#-}"
          [[ "$letters" == *[fP]* ]] && return 1
          [[ "$letters" == *E* ]] && S_FLAV=E
          [[ "$letters" == *F* ]] && S_FLAV=F
          [[ "$letters" == *G* ]] && S_FLAV=G
          [[ "$letters" == *i* ]] && S_CI=1
          [[ "$letters" == *w* ]] && S_W=1
          [[ "$letters" == *x* ]] && S_X=1
          [[ "$letters" == *v* ]] && S_INV=1
          last="${letters: -1}"
          case "$last" in e) pending=1 ;; m|A|B|C|d|D) skip=1 ;; esac
          ;;
      esac
      continue
    fi
    S_PAT="$TOK"; have=1; break
  done
  (( have )) || return 1
  [[ -z "$S_PAT" ]] && return 1
  [[ "$S_PAT" == *[\$\`\'\"]* ]] && return 1
  return 0
}

# $1 = the stage text after `awk`. 0 = S_PAT set (always -E); 1 = fail-open;
# 2 = no regex literal (the argv-slot recipe) — the wrapper is filtered.
sim_awk() {
  local skip=0 prog="" have=0
  S="$1"; S_PAT=""; S_FLAV=E; S_INV=0; S_CI=0; S_W=0; S_X=0
  while :; do
    next_tok; local rc=$?
    (( rc == 2 )) && break
    (( rc == 1 )) && return 1
    if (( skip )); then skip=0; continue; fi
    if (( Q == 0 )) && [[ "$TOK" == -* ]]; then
      case "$TOK" in
        -f|-f*|--file|--file=*) return 1 ;;   # program from a file
        -v|-F)                  skip=1 ;;     # awk's own flags, not grep's
        *)                      : ;;
      esac
      continue
    fi
    prog="$TOK"; have=1; break
  done
  (( have )) || return 1
  [[ "$prog" =~ $RE_AWK ]] || return 2
  S_PAT="${BASH_REMATCH[2]-}"
  [[ -z "$S_PAT" ]] && return 1
  [[ "$S_PAT" == *[\$\`\'\"]* ]] && return 1
  return 0
}

DENY_SNIP=""
# 0 = allow; 1 = deny (DENY_SNIP names the pipeline).
readonly_arm() {
  # Step 0: one bash regex on the raw command before any fork. Commands without
  # a `ps` token at a boundary — the overwhelming majority — pay only this.
  [[ "$CMD" =~ $RE_PS ]] || return 0
  if ! type strip_heredocs >/dev/null 2>&1; then
    echo "WARN: incidents.sh missing — read-only self-match arm skipped (fail-open)" >&2
    return 0
  fi
  local SCAN MODEL rest m after pl psflags stages stage word rc
  SCAN="$(strip_heredocs "$CMD")"
  MODEL="bash -c ${CMD}"
  local -a TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout -k 1 2)
  # The binary by PATH, not the name: `timeout` execs its argument, so a shell
  # builtin (`command`) or the session's grep FUNCTION cannot sit there (rc 127).
  local GREP_BIN; GREP_BIN="$(type -P grep 2>/dev/null || true)"; [[ -n "$GREP_BIN" ]] || return 0

  rest="$SCAN"
  while [[ "$rest" =~ $RE_PS ]]; do
    m="${BASH_REMATCH[0]}"
    after="${rest#*"$m"}"
    rest="$after"
    [[ "$m" == *"|" ]] && after="|$after"
    pl="${after//\|\|/;}"                 # `||` ends a pipeline like `;`
    pl="${pl%%[\;\&\)$NL]*}"              # `;` `&` `)` newline end it too
    [[ "$pl" == *"|"* ]] || continue      # not a pipeline
    psflags="${pl%%|*}"
    stages="${pl#*|}"
    ps_args_showing "$psflags" || continue
    ps_pid_restricted "$psflags" && continue

    local alive=0 filtered=0 bad=0
    while :; do
      if [[ "$stages" == *"|"* ]]; then stage="${stages%%|*}"; stages="${stages#*|}"; else stage="$stages"; stages=""; fi
      stage="${stage#"${stage%%[![:space:]]*}"}"
      word="${stage%%[[:space:]]*}"
      case "$word" in
        grep|egrep|fgrep) sim_grep "$word" "${stage#"$word"}"; rc=$? ;;
        awk)              sim_awk "${stage#awk}"; rc=$? ;;
        *)                break ;;          # a stage that may rewrite the text: stop simulating
      esac
      if (( rc == 1 )); then bad=1; break; fi
      if (( rc == 2 )); then filtered=1; break; fi
      local -a gf=("-$S_FLAV")
      (( S_CI )) && gf+=(-i); (( S_W )) && gf+=(-w); (( S_X )) && gf+=(-x)
      # HERESTRING, never a pipe (#6992 / #7024, grep-q-pipe-guard.test.sh).
      "${TO[@]}" "$GREP_BIN" -q "${gf[@]}" -e "$S_PAT" <<<"$MODEL" 2>/dev/null; rc=$?
      case "$rc" in
        0) if (( S_INV )); then filtered=1; break; else alive=1; fi ;;
        1) if (( S_INV )); then :; else filtered=1; break; fi ;;
        *) bad=1; break ;;                  # 2 invalid regex, 124 timeout, 127 no binary
      esac
      [[ -z "$stages" ]] && break
    done
    (( bad )) && continue
    if (( alive && ! filtered )); then
      DENY_SNIP="ps ${pl}"
      return 1
    fi
  done
  return 0
}

# Does the command use pkill/pgrep with -f? Match the flag in any bundled form
# (-f, -af, -fl) and as a separate token.
# HERESTRING, deliberately (#6992 / #7024, enforced by
# .claude/hooks/grep-q-pipe-guard.test.sh). `grep -q` exits on its first match,
# so a piped producer can die on SIGPIPE — and in a policy gate that reads as
# "no match", i.e. fail-OPEN. A herestring has no producer to kill.
if ! grep -qE "\b(pkill|pgrep)\b[^|;&]*[[:space:]]-[a-zA-Z]*f" <<<"$CMD" 2>/dev/null; then
  # Arm 2 (#8330): the read-only spelling. Runs ONLY on the -f arm's negative
  # path, so a command carrying both spellings yields exactly one envelope.
  if readonly_arm; then exit 0; fi

  reason="BLOCKED: \`ps … | <stage> '<pat>'\` is self-matching here. The Bash tool runs your command as \`bash -c '<the whole command>'\`, so the process list carries a line containing your pattern — the wrapper that issued it, and any sibling watcher spawned the same way. \`<pat>\` matches that line (checked against \`bash -c <your command>\`), so a count never reaches zero and a wait-for-quiet loop reports \"still waiting\" forever.

The \`[t]\` bracket trick protects only the grep process's own argv; it does nothing when the literal appears anywhere else in the same command (an echo, a comment, the runner you launched).

Offending pipeline: ${DENY_SNIP:0:80}

For a one-off look at the box:
  ps … | grep <pat> | grep -v grep     # the wrapper carries \"grep\" by construction, so it drops out
  pgrep -a <name>                      # without -f, matches the process NAME only

For a wait-for-quiet count:
  source plugins/soleur/scripts/lib/proc.sh; list_runs <pattern>
                            # ownership via /proc/<pid>/cwd; excludes self + ancestry
  n=\$(ps -eo args | awk '\$1==\"bash\" && \$2==\"scripts/test-all.sh\"' | wc -l)
                            # argv-SLOT anchor — match the EXACT argv you launched
                            # (\`/usr/bin/bash …\`, \`bash ./scripts/…\` are different slots)
  cmd & pid=\$!; kill -0 \"\$pid\"    # a captured PID names the process exactly"

  emit "pkill-self-match-guard-readonly" deny "${DENY_SNIP:0:80}" "$CMD"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null
  exit 0
fi

TOOL_USED="$(grep -oE '\b(pkill|pgrep)\b' <<<"$CMD" 2>/dev/null | head -1 || echo "pkill")"

reason="BLOCKED: \`${TOOL_USED} -f\` is self-matching here. \`-f\` matches the pattern against the FULL COMMAND LINE of every process, and the Bash tool runs your command as \`bash -c '<the whole command>'\` — so the invoking wrapper's own argv contains your pattern. pkill/pgrep exclude only their own pid, never the parent or a sibling watcher.

Narrowing the pattern does NOT fix it: \`^\` anchors at the start of the joined command line, not at an argv slot, so \`^bash .*foo\\.sh\` still matches a \`bash -c '…foo.sh…'\` watcher (measured, PR #7888).

Use one of:
  source plugins/soleur/scripts/lib/proc.sh
  list_runs                 # enumerate first, decide second
  kill_mine                 # only this worktree's own runs (ownership via /proc/<pid>/cwd)

  cmd & pid=\$!; kill \"\$pid\"    # a captured PID names the process exactly
  ${TOOL_USED} <name>                 # without -f, matches the process NAME only"

jq -nc --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null

exit 0
