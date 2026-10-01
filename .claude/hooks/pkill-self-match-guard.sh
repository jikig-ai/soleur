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
# args-showing, self-listing `ps` stage in SCAN = strip_heredocs(<command>), split
# the pipeline that follows with a QUOTE-AWARE walk (`split_pipeline`): stages are
# separated by an unquoted `|` (or `|&`; a newline right after the pipe is
# allowed), and the pipeline ends at an unquoted `;` `&&` `||` `&` `)` or newline
# (`2>&1`'s `&` is a redirect, not a terminator). Each stage's first word is
# normalised — a leading `\`, a directory prefix, and `command`/`env`/`exec`/
# `nice`/`time`/`timeout`/`nohup`/`stdbuf`/`sudo`/`VAR=x` prefixes are dropped —
# and the walk continues while the word is grep/egrep/fgrep/rg or awk (gawk,
# ugrep, ag …: nobody types them here; `rgrep` ignores stdin). Each matcher
# stage's pattern is run against MODEL with the grep argv the parser built
# (flavour, -i/-w/-x): a non-`-v` stage that matches keeps the wrapper alive; a `-v` stage
# that matches, or a non-`-v` stage that does not, FILTERS the wrapper and the
# pipeline is safe. A grep whose output is not lines (`-c` `-o` `-l` `-L` `-q`)
# ENDS the walk with the verdict so far — a later `| grep -v grep` filters a
# count, not the wrapper, so `grep -c PAT | grep -v grep` still denies. An awk
# with no `/re/` literal (the argv-slot recipe, or a `{print $2}` projection) also
# ends the walk with the verdict so far: `ps | awk '$1=="bash" && $2=="x"'` alone
# is allowed, `ps | grep PAT | awk '{print $2}' | xargs kill` is denied. So does
# any stage that is not a matcher (`wc`, `tee`, `head`, `cut`, `sed`, `perl` …)
# — a stage that may rewrite the text is not simulated. `grep -v grep` filters
# (the wrapper carries "grep" by construction), which is why the work/SKILL.md
# liveness triple `ps -ef | grep -E x | grep -v grep` stays allowed. Verdicts
# OR-accumulate across pipelines: one alive pipeline denies.
#
# Trigger, stage walk and pattern extraction read SCAN; only MODEL reads the raw
# command. Heredoc BODIES are prose being written (a learning, a skill file, this
# header) and must not trigger — the #7994 interaction. They stay IN the model
# because the wrapper carries them: a heredoc mentioning scripts/test-all.sh
# re-arms a bracket-tricked poller in the same command.
#
# A `ps` is at a command boundary when it follows the start of the text, `|`,
# `;`, `&`, `(` (covers `$(`), a backtick, `{`, `!`, a newline, or a shell
# keyword (`while` `until` `if` `elif` `then` `do` `else`), optionally through
# the prefix words above and a directory path. `ps` is args-showing when a bare
# BSD token carries a/x/u (`aux`, `ax`, `x`), a dashed BSD bundle of a/u/x/w
# carries x (`-aux`, `-ax`), a Unix bundle carries f/F (`-ef`, `-F`), or
# -o/-O/--format names args|cmd|command (quoted, `=`-suffixed or `:width`
# forms included). `comm`-only, bare `-e`, `-l` are name-only (no self-match,
# like pgrep without -f). Options that take a value consume it (each is
# commented in `classify_ps`), so `ps -C bash -o comm` is name-only. A ps restricted to
# named pids (-p/--pid/-q/--quick-pid) is exempt — the one ps that cannot list
# the wrapper (`--ppid` is NOT exempt: the wrapper is a child of `$PPID`).
# `-C bash` is not a pid restriction (the wrapper's comm is bash); `-u`/`-t`/`-s`
# can all list it.
#
# Fail-open, PER PIPELINE (`continue`, never `exit`): a literal holding `$`, a
# backtick or a quote; an empty literal; `-f FILE`; `-P`; an unterminated quote;
# the simulation grep returning anything but 0/1 (2 = invalid regex, 124 = the
# 2 s timeout, 127 = no binary). A later pipeline in the same command still gets
# its verdict. The whole arm stops simulating after a 4 s budget (fail-open) so
# a command carrying many pathological patterns cannot exhaust the hook timeout.
# A missing lib/incidents.sh skips the whole arm with a stderr WARN — fail-OPEN,
# not an identity shim (a shim would over-detect exactly when the environment
# is degraded, denying a doc-writing heredoc). The lib is sourced only once a
# `ps` token has been seen, so commands without one pay a single bash regex.
#
# Accepted gaps (name the row when you close one; do not widen silently):
#   * pattern in a variable (incl. awk `-v re=…` / `BEGIN{re=…}`), `-f FILE`,
#     `-P`, a second `-e` (only the first is tested), a `\`-newline-continued
#     stage, `-o` with an attached value (`-oargs`), `-e` in the middle of a
#     bundle (`-ei foo` is read as flags e,i; grep reads pattern `i`).
#   * a pipeline inside a quoted string (`timeout 30 bash -c '…ps…'`, `watch`,
#     `nohup bash -c '…'`, `eval "$CMD"`) or inside an EXECUTED heredoc
#     (`bash <<'EOF'`) — the body is stripped from the trigger scan by design
#     (suite row A17).
#   * `ps … > file; grep pat file` — not a pipeline; a scan written to a FILE
#     and run as `bash /tmp/poll.sh` (genuinely safe: the wrapper argv no longer
#     carries the pattern); `/proc/*/cmdline`, `pstree`, `top` scanners (no `ps`
#     token); `sed -n /re/p`, `perl -ne`, `python -c` matcher stages (the walk
#     ends there, fail-open).
#   * a `;`/`&`/`(` boundary inside a quoted string denies (the boundary regex
#     does not track quotes) — an accepted FALSE DENY, suite row D19; the reason
#     is self-explaining. The same class, in the shape an agent WRITING ABOUT
#     this hook types: a newline or backtick boundary inside `git commit -m "…"`,
#     `gh pr edit --body "…"`, `gh issue comment --body '…'` that merely cites
#     the spelling (suite row D58). A quoted heredoc (`--body "$(cat <<'EOF'`)
#     or `--body-file` carries the same text and is allowed (A17); the reason
#     says so.
#   * awk: `!~` and `!/re/` are read as a match, and a field-restricted
#     `$3 ~ /re/` as a whole-line one (false denies); `IGNORECASE` is ignored; a
#     `/re/` after `=` (`{c+=/re/}`) or a string regex (`$0 ~ "re"`) is not seen
#     (false allow); `-F' '` / `-W posix` attached forms mis-tokenize.
#   * `rg -E <enc>` (encoding, not extended) is read as the grep flag.
#   * the model is prefix-free: a pattern matching only the real wrapper's
#     snapshot preamble or grep-rewrite.sh prefix (`grep -c '[c]laude'`,
#     `'snapshot-bash-[0-9]'`, `'[n]ode_modules'`) self-matches in reality but
#     not here (a false allow); the real argv[0] is /usr/bin/bash, so
#     `-v '^bash -c'` filters the model but not the real line (false allow),
#     while `-v '^/usr/bin/bash -c'`, `-v 'sourc[e]'`, `grep -c '^bash -c'` and
#     `grep -x 'bash -c .*'` deny here but not in reality (false deny); the real
#     wrapper embeds the command through `eval '…'`, so a single quote inside it
#     is rewritten `'"'"'` in argv (a literal containing a quote is a fail-open
#     arm anyway). Two concurrent Bash calls running the same bracket-tricked
#     poller (row A1) self-match each other; the model sees one command.
#   * a pipeline is read from a 4 kB window after `ps` (a longer one cuts its
#     last stage, which then fails open on its quote); the walk copies the
#     command remainder once per `ps` token, so a command that is nothing but
#     thousands of `ps` tokens costs seconds (measured 2 s for 4,000 in 20 kB)
#     — bounded by the 4 s budget, and not a shape anyone types.
#   * a Monitor tool command is not a Bash tool call (work/SKILL.md records it);
#     the Codex harness registers only guardrails.sh (.codex/config.toml), so
#     neither arm runs there; the plugin ships no copy under plugins/soleur/hooks.
#
# Idioms new to this hook set, named so the next reader does not "fix" them:
# the ps walk is a literal `${rest/ps*/}` + substring cursor (siblings iterate
# `grep -o | while read`); `split_pipeline` and `next_tok` are cursor
# tokenizers over globals (TOK_SRC/TOK, STAGES) rather than `$( )` captures,
# because a function called as `x=$(fn)` runs in a subshell and cannot report a
# parse failure through globals (`classify_ps` has a one-bit outcome, so it is
# a return code).
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

# emit_incident wrapper (#8330 arm). lib/incidents.sh is sourced lazily inside
# readonly_arm — its source-time init (a git fork + mkdir) is ~19 ms and only
# `ps`-carrying commands need it. `emit` resolves the function at call time.
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
# Prefix words that can precede `ps` (or a matcher) in a simple command without
# changing what runs: each may carry flag/numeric arguments.
PFX='(sudo|command|env|exec|nice|time|timeout|nohup|setsid|stdbuf|ionice|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)([[:space:]]+[^|;&(){}[:space:]]+)*[[:space:]]+'
# A `ps` token at a command boundary: start of text, `|`, `;`, `&`, `(` (covers
# `$(`), a backtick, `{`, `!`, a newline, or a shell keyword — then optional
# prefix words and a directory path. Never `^` alone (constitution) — the
# boundary set is what keeps `grep -n "ps aux …" README.md` (row A12) out.
# Tested against the (bounded) CONTEXT before each `ps` token plus the token,
# anchored at both ends — never against the whole command (glibc regexec scans
# the full string per call, so a per-token regex over the remainder was O(n·k)).
RE_PS_END="(^|[|;&(!{\`]|${NL}|(^|[[:space:]])(while|until|if|elif|then|do|else)[[:space:]])[[:space:]]*(${PFX})*(/[A-Za-z0-9_./-]*/)?\\\\?ps\$"
# Cheap step-0 pre-trigger over the raw command: a `ps` word followed by a
# space or a pipe, not glued to an identifier (`apps`, `https`, `ps.sh`).
RE_PS_QUICK="(^|[^A-Za-z0-9_.-])ps([[:space:]]|\\|)"
# The first awk regex literal at a regex POSITION (start, whitespace, ~, !, (,
# &, |, ;, {, ,) — not the `/` inside a string like "scripts/test-all.sh".
RE_AWK='(^|[[:space:]~!(&|;{,])/([^/]+)/'

# Stage-simulation state, reset by every sim_* entry. S_ = "stage". S_OPTS is
# the grep argv the simulation runs (flavour first, then -i/-w/-x).
S_RE=""; S_OPTS=(-G); S_INV=0; S_TERM=0
# $1 = the ps stage's flag text. 0 = the listing shows full command lines AND
# is not restricted to named pids (the one ps that cannot list the wrapper).
# One pass; options that take a value consume it so `-C bash` / `-u jean` are
# never read as BSD letter bundles.
classify_ps() {
  local -a toks=(); read -ra toks <<<"$1"
  local tok fmt=0 skipv=0 letters PS_ARGS=0 PS_PID=0
  for tok in ${toks[@]+"${toks[@]}"}; do
    if (( fmt )); then
      fmt=0
      tok="${tok#[\'\"]}"; tok="${tok%[\'\"]}"
      [[ "$tok" =~ (^|,)(args|cmd|command)(=|,|:|$) ]] && PS_ARGS=1
      continue
    fi
    if (( skipv )); then skipv=0; continue; fi
    case "$tok" in
      --format=*) [[ "${tok#--format=}" =~ (^|,)(args|cmd|command)(=|,|:|$) ]] && PS_ARGS=1 ;;
      --format)   fmt=1 ;;
      --pid|--quick-pid) PS_PID=1; skipv=1 ;;
      --pid=*|--quick-pid=*) PS_PID=1 ;;
      --sort|--user|--User|--group|--Group|--tty|--sid|--ppid|--cols|--columns|--width|--lines|--rows) skipv=1 ;;
      --*)        : ;;
      -*)
        letters="${tok#-}"
        [[ "$letters" =~ ^[a-zA-Z]*[fF] ]] && PS_ARGS=1                  # Unix -f / -F / -ef
        [[ "$letters" =~ ^[auxw]+$ && "$letters" == *x* ]] && PS_ARGS=1  # dashed BSD -aux/-ax
        [[ "$letters" =~ ^[a-zA-Z]*[pq] ]] && PS_PID=1                   # -p / -q / -fp
        [[ "$letters" =~ ^[a-zA-Z]*[oO]$ ]] && fmt=1                     # -o / -O / -eo: next token is the format
        [[ "$letters" =~ ^[a-zA-Z]*[CuUgGtspq]$ ]] && skipv=1            # value-taking selectors
        ;;
      *)
        [[ "$tok" =~ ^[a-zA-Z]+$ && "$tok" == *[axu]* ]] && PS_ARGS=1   # BSD aux / ax / x / u
        ;;
    esac
  done
  (( PS_ARGS && ! PS_PID ))
}

# Quote-aware pipeline splitter. $1 = text after the `ps` word. Fills STAGES
# with the ps flag text (STAGES[0]) and each following stage; stops at the
# first unquoted `;` `&&` `||` `&` `)` backtick or newline. `|&` is a pipe; a newline
# right after a pipe is allowed; `>&`/`<&` are redirects. An unterminated
# quote is carried into the stage (next_tok then fails it open).
STAGES=()
split_pipeline() {
  local s="$1" cur="" pre ch
  STAGES=()
  while :; do
    pre="${s%%[\'\"\;\&\)\|\`"$NL"]*}"
    cur+="$pre"; s="${s:${#pre}}"
    [[ -z "$s" ]] && break
    ch="${s:0:1}"; s="${s:1}"
    case "$ch" in
      "'") if [[ "$s" == *"'"* ]]; then cur+="'${s%%\'*}'"; s="${s#*\'}"; else cur+="'$s"; s=""; fi ;;
      '"') if [[ "$s" == *'"'* ]]; then cur+="\"${s%%\"*}\""; s="${s#*\"}"; else cur+="\"$s"; s=""; fi ;;
      '|')
        [[ "${s:0:1}" == "|" ]] && break                     # `||` ends the pipeline
        [[ "${s:0:1}" == "&" ]] && s="${s:1}"               # `|&` is a pipe
        STAGES+=("$cur"); cur=""
        s="${s#"${s%%[![:space:]]*}"}"                       # newline after `|` is allowed
        ;;
      '&')
        if [[ "${cur: -1}" == ">" || "${cur: -1}" == "<" ]]; then cur+="&"; continue; fi   # 2>&1
        break ;;
      *) break ;;                                             # `;` `)` backtick newline
    esac
  done
  STAGES+=("$cur")
}

# Consume one shell-ish token from $TOK_SRC into $TOK (quotes stripped — they
# are shell-level, so a quoted '-v' still reaches grep as -v). Returns 1 on an
# unterminated quote (fail-open), 2 at end.
TOK_SRC=""; TOK=""
next_tok() {
  TOK_SRC="${TOK_SRC#"${TOK_SRC%%[![:space:]]*}"}"
  [[ -z "$TOK_SRC" ]] && return 2
  local r
  case "$TOK_SRC" in
    "'"*) r="${TOK_SRC#\'}"; [[ "$r" == *"'"* ]] || return 1; TOK="${r%%\'*}"; TOK_SRC="${r#*\'}" ;;
    '"'*) r="${TOK_SRC#\"}"; [[ "$r" == *'"'* ]] || return 1; TOK="${r%%\"*}"; TOK_SRC="${r#*\"}" ;;
    *)    TOK="${TOK_SRC%%[[:space:]]*}"; TOK_SRC="${TOK_SRC#"$TOK"}" ;;
  esac
  return 0
}

# A resolvable pattern literal: non-empty, no `$`/backtick/quote (those need a
# shell to evaluate). 1 = fail-open.
literal_ok() { [[ -n "$1" && "$1" != *[\$\`\'\"]* ]]; }

# Stage command word: strips `\`, a directory prefix, and prefix words. Sets
# WORD and WORD_REST (the stage text after the word).
WORD=""; WORD_REST=""
stage_word() {
  local s="$1" w pfx=0
  while :; do
    s="${s#"${s%%[![:space:]]*}"}"
    w="${s%%[[:space:]]*}"; s="${s#"$w"}"
    [[ -z "$w" ]] && { WORD=""; WORD_REST=""; return; }
    w="${w#\\}"; w="${w##*/}"
    case "$w" in
      command|env|exec|nice|time|timeout|nohup|setsid|stdbuf|ionice|sudo) pfx=1; continue ;;
      [A-Za-z_]*=*) pfx=1; continue ;;
      -*|[0-9]*) (( pfx )) && continue ;;
    esac
    WORD="$w"; WORD_REST="$s"; return
  done
}

# $1 = matcher word, $2 = the stage text after it. 0 = S_* set; 1 = fail-open.
sim_grep() {
  local word="$1" pending=0 skip=0 dd=0 have=0 letters last rc
  TOK_SRC="$2"; S_RE=""; S_OPTS=(-G); S_INV=0; S_TERM=0
  case "$word" in egrep|rg) S_OPTS=(-E) ;; fgrep) S_OPTS=(-F) ;; esac
  while :; do
    next_tok; rc=$?
    (( rc == 2 )) && break
    (( rc == 1 )) && return 1
    if (( pending )); then S_RE="$TOK"; have=1; break; fi
    if (( skip )); then skip=0; continue; fi
    if (( dd == 0 )) && [[ "$TOK" == -* ]]; then
      case "$TOK" in
        --)                       dd=1 ;;
        -e|--regexp|--reg|--rege|--regex) pending=1 ;;
        --regexp=*|--reg=*|--rege=*|--regex=*) S_RE="${TOK#*=}"; have=1; break ;;
        -f|-P|--fil*|--per*)      return 1 ;;
        --ext*)                   S_OPTS[0]=-E ;;
        --fix*)                   S_OPTS[0]=-F ;;
        --bas*)                   S_OPTS[0]=-G ;;
        --ign*)                   S_OPTS+=(-i) ;;
        --inv*)                   S_INV=1 ;;
        --wor*)                   S_OPTS+=(-w) ;;
        --lin*)                   S_OPTS+=(-x) ;;
        --cou*|--onl*|--qui*|--sil*) S_TERM=1 ;;
        --max-count|--context|--after-context|--before-context) skip=1 ;;
        --*)                      : ;;
        -*)
          letters="${TOK#-}"
          if [[ "$letters" == e?* ]]; then S_RE="${letters#e}"; have=1; break; fi   # -epat (attached)
          [[ "$letters" == *[fP]* ]] && return 1
          [[ "$letters" == *E* ]] && S_OPTS[0]=-E
          [[ "$letters" == *F* ]] && S_OPTS[0]=-F
          [[ "$letters" == *G* ]] && S_OPTS[0]=-G
          [[ "$letters" == *i* ]] && S_OPTS+=(-i)
          [[ "$letters" == *w* ]] && S_OPTS+=(-w)
          [[ "$letters" == *x* ]] && S_OPTS+=(-x)
          [[ "$letters" == *v* ]] && S_INV=1
          [[ "$letters" == *[colLq]* ]] && S_TERM=1
          last="${letters: -1}"
          case "$last" in e) pending=1 ;; m|A|B|C|d|D) skip=1 ;; esac
          ;;
      esac
      continue
    fi
    S_RE="$TOK"; have=1; break
  done
  literal_ok "$S_RE"
}

# $1 = the stage text after `awk`. 0 = S_RE set (always -E); 1 = fail-open;
# 2 = no regex literal (argv-slot recipe or a projection) — the walk ends with
# the verdict so far.
sim_awk() {
  local skip=0 prog="" have=0 rc
  TOK_SRC="$1"; S_RE=""; S_OPTS=(-E); S_INV=0; S_TERM=0
  while :; do
    next_tok; rc=$?
    (( rc == 2 )) && break
    (( rc == 1 )) && return 1
    if (( skip )); then skip=0; continue; fi
    if [[ "$TOK" == -* ]]; then
      case "$TOK" in
        -f*|--file|--file=*) return 1 ;;   # program from a file
        -v|-F|-W)            skip=1 ;;     # awk's own flags, not grep's
        *)                   : ;;
      esac
      continue
    fi
    prog="$TOK"; have=1; break
  done
  (( have )) || return 1
  [[ "$prog" =~ $RE_AWK ]] || return 2
  S_RE="${BASH_REMATCH[2]}"
  literal_ok "$S_RE" || return 1
  return 0
}

DENY_SNIP=""; DENY_STAGE=""
# 0 = allow; 1 = deny (DENY_SNIP names the pipeline, DENY_STAGE the stage).
readonly_arm() {
  # Step 0: one bash regex on the raw command before any fork. Commands without
  # a `ps` token at a boundary — the overwhelming majority — pay only this.
  [[ "$CMD" =~ $RE_PS_QUICK ]] || return 0
  # strip_heredocs + emit_incident. Fail-soft: absent lib → WARN + skip the arm.
  . "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true
  if ! type strip_heredocs >/dev/null 2>&1; then
    echo "WARN: incidents.sh missing — read-only self-match arm skipped (fail-open)" >&2
    return 0
  fi
  local scan model rest pre after ctx pl stage rc i t0=$SECONDS
  # Byte-indexed string ops: under a UTF-8 locale every substring/pattern op
  # walks characters (measured ~10x slower on a 20 kB remainder); the
  # simulation greps then also run bytewise, which the wrapper model is.
  local LC_ALL=C
  scan="$(strip_heredocs "$CMD")"
  model="bash -c ${CMD}"
  local -a to=(); [[ -n "$(type -P timeout 2>/dev/null)" ]] && to=(timeout -k 1 2)   # a binary: the subshell execs it
  # The binary by PATH, not the name: `timeout` execs its argument, so a shell
  # builtin (`command`) or the session's grep FUNCTION cannot sit there (rc 127).
  local grep_bin; grep_bin="$(type -P grep 2>/dev/null || true)"; [[ -n "$grep_bin" ]] || return 0

  rest="$scan"
  while :; do
    (( SECONDS - t0 >= 4 )) && return 0        # budget exhausted: fail-open
    # Next literal `ps`, then judge the boundary on a bounded context window.
    # `${rest/ps*/}` (first match, then substring) is the fast idiom: measured
    # on 100 kB — `${rest#*ps}` 2.8 s (quadratic), `${rest%%ps*}` 262 ms
    # (fnmatch per position), `${rest/ps*/}` 6 ms.
    pre="${rest/ps*/}"
    [[ "$pre" == "$rest" ]] && break           # no further `ps`
    after="${rest:${#pre}+2}"
    rest="$after"
    case "${after:0:1}" in ' '|$'\t'|'|') ;; *) continue ;; esac
    # Judge the boundary on a bounded window; `${pre: -256}` is EMPTY when pre is
    # shorter, so the branch is load-bearing. `#` sentinel: a truncated window
    # never reads as start-of-text.
    if (( ${#pre} > 256 )); then ctx="#${pre: -256}"; else ctx="$pre"; fi
    [[ "${ctx}ps" =~ $RE_PS_END ]] || continue
    pl="${after:0:4096}"                       # a pipeline is short; a cut stage fails open on its quote
    split_pipeline "$pl"
    (( ${#STAGES[@]} >= 2 )) || continue        # not a pipeline
    classify_ps "${STAGES[0]}" || continue

    local alive=0 filtered=0 bad=0
    for (( i = 1; i < ${#STAGES[@]}; i++ )); do
      stage="${STAGES[i]}"
      stage_word "$stage"
      case "$WORD" in
        grep|egrep|fgrep|rg) sim_grep "$WORD" "$WORD_REST"; rc=$? ;;
        awk)                 sim_awk "$WORD_REST"; rc=$? ;;
        *)                   break ;;   # a stage that may rewrite the text: stop simulating
      esac
      if (( rc == 1 )); then bad=1; break; fi
      if (( rc == 2 )); then break; fi           # no regex: the walk ends with the verdict so far
      # HERESTRING, never a pipe (#6992 / #7024, grep-q-pipe-guard.test.sh).
      # Address-space cap: GNU grep expands bounded repetition eagerly and a
      # group-free `.{1,32767}.{1,32767}b` reached 4.2 GB inside the 2 s window
      # (measured); ENOMEM → rc 2 → the fail-open arm below.
      ( ulimit -v 262144 2>/dev/null; exec ${to[@]+"${to[@]}"} "$grep_bin" -q "${S_OPTS[@]}" -e "$S_RE" <<<"$model" 2>/dev/null ); rc=$?
      case "$rc" in
        0) if (( S_INV )); then filtered=1; break; else alive=1; DENY_STAGE="$WORD '$S_RE' (${S_OPTS[0]})"; fi ;;
        1) if (( S_INV )); then :; else filtered=1; break; fi ;;
        *) bad=1; break ;;                       # 2 invalid regex, 124 timeout, 127 no binary
      esac
      (( S_TERM )) && break                      # -c/-o/-l/-L/-q: later stages see a count, not lines
    done
    (( bad )) && continue
    if (( alive && ! filtered )); then
      local seg
      DENY_SNIP="ps"
      for (( i = 0; i < ${#STAGES[@]}; i++ )); do
        seg="${STAGES[i]#"${STAGES[i]%%[![:space:]]*}"}"; seg="${seg%"${seg##*[![:space:]]}"}"
        (( i == 0 )) && DENY_SNIP+=" $seg" || DENY_SNIP+=" | $seg"
      done
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

Offending pipeline: ${DENY_SNIP:0:160}
Matching stage:     ${DENY_STAGE:0:120}

For a one-off look at the box:
  ps … | grep <pat> | grep -v grep     # the wrapper carries \"grep\" by construction, so it drops out
                                       # (put the -v BEFORE any -c: a count cannot be filtered)
  pgrep -a <name>                      # without -f, matches the process NAME (comm) only —
                                       # a script run as \`bash x.sh\` is named bash, so use the awk slot below

For a wait-for-quiet count:
  source plugins/soleur/scripts/lib/proc.sh; list_runs <pattern>
                            # ownership via /proc/<pid>/cwd; excludes self + ancestry
  n=\$(ps -eo args | awk '\$1==\"bash\" && \$2==\"scripts/test-all.sh\"' | wc -l)
                            # argv-SLOT anchor — match the EXACT argv you launched
                            # (\`/usr/bin/bash …\`, \`bash ./scripts/…\` are different slots)
  until [ -s \"\$RCF\" ]; do sleep 30; done   # rc FILE written as the runner's last act (ship/SKILL.md)
  cmd & pid=\$!; kill -0 \"\$pid\"    # a captured PID names the process exactly — NOT under
                                     # setsid/nohup wrappers, where \$! is the forked parent

Only WRITING about this shape (a commit message, a PR body, an issue comment)? Put the text in a quoted heredoc or a file: \`--body \"\$(cat <<'EOF' … EOF)\"\`, \`--body-file\`, \`-F msg.txt\` — a heredoc body is not scanned."

  emit "pkill-self-match-guard-readonly" deny "pkill-self-match-guard: read-only ps pipeline matches its own wrapper" "$CMD"
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
