#!/usr/bin/env bash
# Tests for .claude/hooks/lib/filing-shape.pl — the filing gate's shell lexer
# (#9089, ADR-256).
#
# WHERE A NEW ROW GOES:
#   * a gh SPELLING (a POST signal, an endpoint form, a create alias)
#       -> .claude/hooks/lib/filing-shape-corpus.json. Both this suite and the
#          vitest parity suite run every row, so the cron mirror sees it too.
#   * LEXING (where bash would run a filing, what is prose, a field's value)
#       -> this file, as a lexer-record row.
#   * a VERDICT or a refusal TEXT -> .claude/hooks/guardrails.test.sh.
#
# MODES:
#   (none)                          the suite.
#   --probe                         one lexer call on `URL=$(gh issue create
#                                   --title x)`; prints PROBE=<shape> (the plan's
#                                   discoverability probe — Check 10 allows bash,
#                                   not perl).
#   --differential <base-hooks-dir> opt-in, not CI: executes generated commands
#                                   under a logging gh shim and compares what gh
#                                   actually received (ground truth from gh
#                                   semantics, NOT from --classify) with the
#                                   lexer's findings, then prints the base-vs-
#                                   patched hook flip table.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

LIB="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PL="$LIB/filing-shape.pl"
CORPUS="$LIB/filing-shape-corpus.json"

if [[ "${1:-}" == "--probe" ]]; then
  _probe="$(printf '%s' 'URL=$(gh issue create --title x)' | perl "$PL" 2>/dev/null | tr '\0' '\n' | sed -n 2p)"
  echo "PROBE=${_probe:-none}"
  exit 0
fi

if [[ "${1:-}" == "--differential" ]]; then
  # The EXECUTED oracle (AC5). Not CI: it runs ~1,000 generated commands.
  # Ground truth is what a logging gh shim RECEIVED, judged by gh semantics
  # below — independent of --classify, so a predicate weakened in step with the
  # corpus still shows up as a miss. The generated commands must never reach a
  # real gh: shims come first on PATH, no generated command names an absolute
  # gh path, and GH_TOKEN/GH_HOST/GH_CONFIG_DIR point nowhere.
  BASE_HOOKS="${2:-}"
  [[ -n "$BASE_HOOKS" && -f "$BASE_HOOKS/guardrails.sh" ]] || {
    echo "usage: $0 --differential <base-hooks-dir>   (e.g. a git archive of 4170460eea:.claude/hooks)" >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing" >&2; exit 3; }
  DW="$(mktemp -d)"; trap 'rm -rf "$DW"' EXIT
  mkdir -p "$DW/bin" "$DW/cwd" "$DW/ghcfg"
  cat > "$DW/bin/gh" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\037' "$a"; done >> "$GHLOG"
printf '\036' >> "$GHLOG"
exit 0
SH
  printf '#!/bin/sh\nexec "$@"\n' > "$DW/bin/sudo"
  printf '#!/bin/sh\nwhile [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done\n[ $# -gt 0 ] && shift\nexec "$@"\n' > "$DW/bin/doppler"
  printf '#!/bin/sh\nexit 0\n' > "$DW/bin/git"
  chmod +x "$DW/bin/"*

  # truth LOGFILE -> one line per gh call: create|api|none (gh semantics).
  truth_of() {
    perl -e '
      local $/; open my $f, "<", $ARGV[0] or exit 0; my $all = <$f>; $all = "" unless defined $all;
      for my $call (split /\x1e/, $all) {
        my @a = split /\x1f/, $call, -1; pop @a if @a && $a[-1] eq "";
        my (@pos, $method, $fields, $input, $title) = ();
        for (my $i = 0; $i < @a; $i++) {
          my $t = $a[$i];
          if ($t eq "-R" || $t eq "--repo") { $i++; next }
          if ($t =~ /^-(?:i*X|-method)$/) { $method = $a[++$i]; next }
          if ($t =~ /^(?:-i*X=?|--method=)(.+)$/) { $method = $1; next }
          if ($t =~ /^--input(?:=|$)/) { $input = 1; $i++ if $t eq "--input"; next }
          if ($t =~ /^(?:-i*[fF]|--field|--raw-field)$/) { my $v = $a[++$i] // ""; $fields = 1; $title = 1 if $v =~ /^title=/; next }
          if ($t =~ /^(?:-i*[fF]=?|--field=|--raw-field=)(.*)$/s) { $fields = 1; $title = 1 if $1 =~ /^title=/; next }
          if ($t =~ /^-/) { $i++ if $t =~ /^-(?:[qHpt]|-jq|-header|-preview|-template|-cache|-hostname|-title|-body|-body-file|-label|-milestone|-assignee|-project)$/; next }
          push @pos, $t;
        }
        if (@pos >= 2 && $pos[0] eq "issue" && ($pos[1] eq "create" || $pos[1] eq "new")) { print "create\n"; next }
        if (@pos >= 2 && $pos[0] eq "api") {
          my $p = $pos[1]; $p =~ s{^https?://[^/]+/}{}; $p =~ s{^/}{}; $p =~ s{[?#].*}{}s;
          $p =~ s{\{owner\}/\{repo\}}{jikig-ai/soleur}; 1 while $p =~ s{(^|/)[^/]+/\.\.(/|$)}{$1}; $p =~ s{(^|/)\./}{$1}g; $p =~ s{%2[eE]%2[eE]/}{}g;
          my $post = defined $method ? ($method =~ /^post$/i) : ($fields || $input);
          if ($p =~ m{^(?:repos/[^/]+/[^/]+|repositories/\d+)/issues/?$} && $post && ($title || $input)) { print "api\n"; next }
        }
        print "none\n";
      }' "$1"
  }

  # Commands: 12 wrappers x (the corpus's create/api rows + 10 none rows), plus prose.
  sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
  tok_word() {
    if [[ "$1" == *'$'* || "$1" == *'`'* ]]; then printf '%s' "$1"
    elif [[ "$1" =~ ^[A-Za-z0-9_/.:=@%+,-]+$ ]]; then printf '%s' "$1"
    else sq "$1"; fi
  }
  dq_esc() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//\$/\\\$}"; s="${s//\`/\\\`}"; printf '%s' "$s"; }
  bt_esc() { local s="${1//\\/\\\\}"; s="${s//\`/\\\`}"; printf '%s' "$s"; }
  WRAPPERS=(bare subst qsubst backtick bash-c sh-c eval sudo setsid doppler pipe heredoc)
  wrap() {
    case "$1" in
      bare)     printf '%s' "$2" ;;
      subst)    printf 'X=$(%s)' "$2" ;;
      qsubst)   printf 'X="$(%s)"' "$2" ;;
      backtick) printf 'X=`%s`' "$(bt_esc "$2")" ;;
      bash-c)   printf 'bash -c "%s"' "$(dq_esc "$2")" ;;
      sh-c)     printf 'sh -c %s' "$(sq "$2")" ;;
      eval)     printf 'eval "%s"' "$(dq_esc "$2")" ;;
      sudo)     printf 'sudo %s' "$2" ;;
      setsid)   printf 'setsid -w %s' "$2" ;;
      doppler)  printf 'doppler run -- %s' "$2" ;;
      pipe)     printf 'printf x | %s' "$2" ;;
      heredoc)  printf 'cat <<EOF\n$(%s)\nEOF' "$2" ;;
    esac
  }
  CMDS=(); COLS=(); KINDS=()
  while IFS= read -r row; do
    mapfile -d '' toks < <(jq -j '.tokens[] | . + "\u0000"' <<<"$row")
    s=""; for t in "${toks[@]}"; do s+="${s:+ }$(tok_word "$t")"; done
    for w in "${WRAPPERS[@]}"; do CMDS+=("$(wrap "$w" "$s")"); COLS+=("$w"); KINDS+=(corpus); done
    # A title-bearing twin of every api row, so ground truth (which requires a
    # title or --input, as GitHub does) covers the ENDPOINT axis too: without
    # it every endpoint-form row read as "no filing" and a weakened endpoint
    # predicate could not show up as a miss (#9089 test-design review).
    if [[ "$(jq -r '.shape' <<<"$row")" == api ]]; then
      for w in "${WRAPPERS[@]}"; do CMDS+=("$(wrap "$w" "$s -f title=x")"); COLS+=("$w"); KINDS+=(corpus); done
    fi
  done < <(jq -c '[.[] | select(has("id") and .shape != "none")] + ([.[] | select(has("id") and .shape == "none")] | .[:10]) | .[]' "$CORPUS")
  PROSE=(
    $'git commit -m "$(cat <<\'EOF\'\nfix: it\'s 1) done ( `x` $( "q"\ngh issue create --title x --body y\nEOF\n)"'
    $'git commit -m "$(cat <<"EOF"\ngh issue create --title x\nEOF\n)"'
    $'git commit -F - <<\'EOF\'\ngh api repos/jikig-ai/soleur/issues -X POST -f title=x\nEOF'
    "echo 'done; gh issue create --title x --body y'"
    'echo "a; gh issue create --title x"'
    'echo "${M:-a; gh issue create --title x}"'
    'echo x # $(gh issue create --title x)'
    'git commit -m "fix: do not run gh issue create"'
    'echo "gh issue create --title x"'
    'grep -n "gh issue create" /dev/null'
    'gh pr create --title "gh issue create" --body x'
    "printf '%s\n' 'gh issue create --title x' > notes.md"
    "gh issue list --json title --jq '.[] | \"it'\\''s\"'"
    "gh api 'repos/jikig-ai/soleur/issues?labels=x' --jq '.[].number' | xargs -I{} gh api -X POST repos/jikig-ai/soleur/issues/{}/labels -f 'labels[]=y'"
    'gh api repos/{owner}/{repo}/issues --jq length'
    'gh api repos/jikig-ai/soleur/issues/1/comments -X POST -f body=x'
    'gh api repos/jikig-ai/soleur/issues/1/labels -X POST -f "labels[]=x"'
    'gh api repos/jikig-ai/soleur/pulls -X POST -f title=x'
    'gh api repos/jikig-ai/soleur/issues.json -X POST -f title=x'
    'gh issue view 1 --json body --jq .body'
    "cat <<'EOF' > notes.md"$'\n$(gh issue create --title x)\nEOF'
    'x="gh issue create"; echo "$x"'
    "sh -c 'echo \"gh issue create\"'"
    'bash -c "echo \"gh api repos/o/r/issues -X POST\""'
    'gh issue list --label meta/machinery --milestone x'
    'gh api graphql -f query="{ viewer { login } }"'
    'gh issue comment 1 --body "gh issue create --title x"'
    'git log --grep "gh issue create" -1'
  )
  for p in "${PROSE[@]}"; do CMDS+=("$p"); COLS+=(prose); KINDS+=(prose); done
  # Deliberate over-fire (DC-2): an unquoted `echo gh issue create` that bash
  # runs. Not prose, not a filing -- reported in the flip table, never a miss.
  for p in 'echo "$(echo gh issue create)"' 'echo `echo gh issue create`'; do CMDS+=("$p"); COLS+=(overfire); KINDS+=(overfire); done

  lexcount() { printf '%s' "$1" | perl "$PL" 2>/dev/null | tr '\0' '\n' | grep -cx 'F'; }
  hookdec() {
    local hooks="$1" cmd="$2" out
    out="$(cd "$DW/cwd" && printf '%s' "$cmd" | jq -Rsc '{tool_name:"Bash", tool_input:{command:.}}' \
      | INCIDENTS_REPO_ROOT="$DW" bash "$hooks/guardrails.sh" 2>/dev/null)"
    [[ -z "${out//[[:space:]]/}" ]] && { echo "allow"; return; }
    jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" 2>/dev/null || echo "?"
  }
  export REPO=jikig-ai/soleur M=POST EP=repos/jikig-ai/soleur/issues QS='?x=1' B=repos/jikig-ai/soleur T='title=x' E=
  misses=0; prose_hits=0; n=0; unexplained=0
  declare -A COLTRUTH=()
  FLIPS=()
  for i in "${!CMDS[@]}"; do
    cmd="${CMDS[$i]}"; n=$((n + 1))
    : > "$DW/gh.log"
    (cd "$DW/cwd" && GHLOG="$DW/gh.log" GH_TOKEN=invalid GH_HOST=invalid.invalid GH_CONFIG_DIR="$DW/ghcfg" \
      PATH="$DW/bin:/usr/bin:/bin" timeout 5 bash -c "$cmd" </dev/null >/dev/null 2>&1)
    tf="$(truth_of "$DW/gh.log" | grep -cvx none || true)"
    lc="$(lexcount "$cmd")"
    [[ "$tf" -gt 0 ]] && COLTRUTH[${COLS[$i]}]=1
    if [[ "${KINDS[$i]}" == prose ]]; then
      if [[ "$lc" -gt 0 ]]; then prose_hits=$((prose_hits + 1)); echo "PROSE-FILING: ${cmd//$'\n'/⏎}"; fi
    elif (( tf > lc )); then
      misses=$((misses + 1)); echo "MISS [${COLS[$i]}] truth=$tf lexer=$lc: ${cmd//$'\n'/⏎}"
    fi
    bd="$(hookdec "$BASE_HOOKS" "$cmd")"; pd="$(hookdec "$LIB/.." "$cmd")"
    if [[ "$bd" != "$pd" ]]; then
      # Every flip must be EXPLAINED (AC5); an unexplained one fails the run.
      why="UNEXPLAINED"
      if [[ "$bd" == allow && "$pd" == deny ]]; then
        # Explanations come from the COMMAND and ground truth, never from the
        # lexer's own count (that made every over-gate self-certifying).
        if (( tf > 0 )); then why="oracle-truth filing"
        elif [[ "$cmd" == *"echo gh issue create"* || "$cmd" == *"echo \`echo gh"* ]]; then why="DC-2 over-fire"
        elif [[ "$cmd" != *title=* && "$cmd" != *--input* ]]; then why="over-gate: a POST signal with no title field (GitHub rejects it; the predicate errs toward gating)"
        elif [[ "$cmd" == *'`cat t`'* || "$cmd" == *'cat t\`'* || "$cmd" == *'-X$M'* || "$cmd" == *'-X=$M'* ]]; then why="over-gate: an unknowable \$/backtick value"
        elif [[ "$cmd" == *'/..;/'* ]]; then why="policy deny: a dot-segment endpoint (servers normalize ..; differently)"
        elif [[ "$cmd" == *'/issues title=x'* ]]; then why="over-gate: a bare title= positional (gh rejects the extra arg; corpus C51)"
        elif [[ "$cmd" == *'repos/o/issues'* ]]; then why="over-gate: a one-segment repos/o/issues path (corpus C85)"
        fi
      elif [[ "$bd" == deny && "$pd" == allow ]]; then
        if [[ "$cmd" =~ (-m|--milestone)[[:space:]=] && "$cmd" == *meta/machinery* ]]; then why="justified filing (-m / machinery label)"
        elif (( tf == 0 )); then why="not a filing (ground truth)"
        fi
      fi
      [[ "$why" == UNEXPLAINED ]] && unexplained=$((unexplained + 1))
      FLIPS+=("$bd -> $pd | $why | truth=$tf | ${COLS[$i]} | ${cmd//$'\n'/⏎}")
    fi
  done
  empty_cols=0
  for w in "${WRAPPERS[@]}"; do
    [[ -n "${COLTRUTH[$w]:-}" ]] || { empty_cols=$((empty_cols + 1)); echo "EMPTY-COLUMN: $w produced no truth filing (cannot fail, so it is a failure)"; }
  done
  echo
  echo "## Flip table (base -> patched), ${#FLIPS[@]} flips"
  printf '%s\n' "${FLIPS[@]}" | awk -F' [|] ' '{print $1" | "$2}' | sort | uniq -c | sort -rn
  echo
  printf '%s\n' "${FLIPS[@]}" | grep -F 'UNEXPLAINED' | cut -c1-220
  echo
  echo "DIFFERENTIAL: commands=$n misses=$misses prose_filings=$prose_hits empty_columns=$empty_cols flips=${#FLIPS[@]} unexplained=$unexplained"
  (( n >= 300 && misses == 0 && prose_hits == 0 && empty_cols == 0 && unexplained == 0 )) || exit 1
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v perl >/dev/null 2>&1 || { echo "UNRESOLVED: perl missing — this suite asserted nothing"; exit 3; }

PASS=0
FAIL=0
TOTAL=0
pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/  /'; }

# Instrument self-test: both helpers must move their counters, or every
# verdict below is unmeasured. Reported with printf + exit, never via fail().
pass "self-test pass" >/dev/null; fail "self-test fail" >/dev/null
if [[ "$PASS" != 1 || "$FAIL" != 1 || "$TOTAL" != 2 ]]; then
  printf 'INSTRUMENT: pass/fail helpers did not count (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 1
fi
PASS=0; FAIL=0; TOTAL=0

# lex CMD -> the lexer's stream, parsed BY COUNT into lines:
#   F <shape> <ctx> <field>|<field>…
#   OK | E <cause>
#   RC <n>
lex() {
  local cmd="$1" x out="" i=0 nf j
  local -a it=()
  while IFS= read -r -d '' x; do it+=("$x"); done < <(printf '%s' "$cmd" | perl "$PL" 2>/dev/null; printf 'RC\0%s\0' "$?")
  while (( i < ${#it[@]} )); do
    case "${it[$i]}" in
      F)
        nf="${it[$((i + 3))]:-0}"
        [[ "$nf" =~ ^[0-9]+$ ]] || { out+="MALFORMED"$'\n'; break; }
        local -a fs=()
        for (( j = 0; j < nf; j++ )); do
          x="${it[$((i + 4 + j))]:-}"
          fs+=("$x")
        done
        out+="F ${it[$((i + 1))]} ${it[$((i + 2))]} $(IFS='|'; echo "${fs[*]}")"$'\n'
        i=$((i + 4 + nf)) ;;
      OK) out+="OK"$'\n'; i=$((i + 1)) ;;
      E)  out+="E ${it[$((i + 1))]:-}"$'\n'; i=$((i + 2)) ;;
      RC) out+="RC ${it[$((i + 1))]:-}"; i=$((i + 2)) ;;
      *)  out+="JUNK ${it[$i]}"$'\n'; i=$((i + 1)) ;;
    esac
  done
  printf '%s' "$out"
}

# want_lex LABEL CMD EXPECTED — exact stream (expected omits the trailing RC
# line when it is "OK\nRC 0"; pass the full text otherwise).
want_lex() {
  local label="$1" cmd="$2" want="$3" got
  got="$(lex "$cmd")"
  [[ "$want" == *$'\nRC '* || "$want" == "RC "* ]] || want="$want"$'\nOK\nRC 0'
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label" "want: ${want//$'\n'/ ⏎ }"$'\n'"got:  ${got//$'\n'/ ⏎ }"; fi
}

# want_prose LABEL CMD — lexes cleanly (exit 0 + OK) and finds NO filing.
want_prose() {
  local label="$1" cmd="$2" got
  got="$(lex "$cmd")"
  if [[ "$got" == $'OK\nRC 0' ]]; then pass "$label"; else fail "$label" "want: OK ⏎ RC 0"$'\n'"got:  ${got//$'\n'/ ⏎ }"; fi
}

# want_shapes LABEL CMD "shape ctx[,shape ctx…]" — the records' shape+ctx only.
want_shapes() {
  local label="$1" cmd="$2" want="$3" got
  got="$(lex "$cmd" | awk '/^F /{printf "%s%s %s", (n++ ? "," : ""), $2, $3} /^RC /{rc=$2} /^OK$/{ok=1} END{printf "|ok=%s rc=%s", ok+0, rc}')"
  if [[ "$got" == "$want|ok=1 rc=0" ]]; then pass "$label"; else fail "$label" "want: $want|ok=1 rc=0"$'\n'"got:  $got"; fi
}

# ---------------------------------------------------------------------------
# 0. The file compiles.
if perl -c "$PL" >/dev/null 2>&1; then pass "L0 perl -c filing-shape.pl"; else fail "L0 perl -c filing-shape.pl" "$(perl -c "$PL" 2>&1 | head -5)"; fi

# ---------------------------------------------------------------------------
# 1. Corpus parity (Guard 3). Every row through --classify; the floor counts
#    EXECUTED rows, and all three classes must be among the ASSERTED rows.
CORPUS_RAN=0
declare -A CLASSES=()
while IFS= read -r row; do
  id="$(jq -r '.id' <<<"$row")"
  want="$(jq -r '.shape' <<<"$row")"
  mapfile -d '' toks < <(jq -j '.tokens[] | . + "\u0000"' <<<"$row")
  got="$(perl "$PL" --classify "${toks[@]}" 2>&1)"
  CORPUS_RAN=$((CORPUS_RAN + 1))
  CLASSES[$want]=1
  if [[ "$got" == "$want" ]]; then pass "corpus $id ($want)"; else fail "corpus $id: $(jq -c '.tokens' <<<"$row")" "want: $want  got: $got"; fi
done < <(jq -c '.[] | select(has("id"))' "$CORPUS")
CORPUS_FLOOR=115
if (( CORPUS_RAN < CORPUS_FLOOR )); then
  printf 'FLOOR: only %s corpus rows executed, expected at least %s\n' "$CORPUS_RAN" "$CORPUS_FLOOR" >&2
  exit 1
fi
if [[ -n "${CLASSES[create]:-}" && -n "${CLASSES[api]:-}" && -n "${CLASSES[none]:-}" ]]; then
  pass "corpus: all three classes asserted"
else
  fail "corpus: all three classes asserted" "classes: ${!CLASSES[*]}"
fi

# ---------------------------------------------------------------------------
# 2. Lexer-record rows. Row IDs are the plan's Test Scenarios IDs.
J=' --milestone "Post-MVP / Later" --label meta/machinery'
K=' --milestone M --label meta/machinery'
EP=repos/jikig-ai/soleur/issues

# Substitutions and runners
want_shapes "D1 unquoted \$(…)"              'URL=$(gh issue create --title x --body y)' "create subst"
want_shapes "D2 quoted \"\$(…)\""            'URL="$(gh issue create --title x --body y)"' "create subst"
want_shapes "D3 api in quoted \$(…)"         "N=\"\$(gh api $EP -X POST -f title=x -f body=y)\"" "api subst"
want_shapes "D4 bash -c \"…\""               'bash -c "gh issue create --title x --body y"' "create shell-c"
want_shapes "D5 sh -c '…'"                   "sh -c 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D6 bash -lc cluster"            "bash -lc 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D7 backticks"                   'echo `gh issue create --title x --body y`' "create backtick"
want_shapes "D19 eval"                       'eval "gh issue create --title x --body y"' "create eval"
want_shapes "D20 escaped \$( in bash -c"     'bash -c "URL=\$(gh issue create --title x --body y)"' "create subst"
want_shapes "D23 \$(…) inside \${:-}"        'X="${Y:-$(gh issue create --title x --body y)}"' "create subst"
want_shapes "D31a bash -c --"                "bash -c -- 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D31b bash --norc -c"            "bash --norc -c 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D31c sudo sh -c"                "sudo sh -c 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D51 bash -c -o posix"           "bash -c -o posix 'gh issue create --title x --body y'" "create shell-c"
want_shapes "D52a \$'\\'' ends where bash ends it" "echo \$'\\''; gh issue create --title x --body y -m M # '" "create top"
want_shapes "D52b \$\"\$(…)\" is live"       'echo $"$(gh issue create --title x --body y)"' "create subst"

# Quoted spellings and deliberate over-fire
want_shapes "D8 quoted endpoint"             "gh api \"$EP\" -X POST -f title=x -f body=y" "api top"
want_shapes "D9 repos/\"\$REPO\"/issues"     'gh api repos/"$REPO"/issues -X POST -f title=x' "api top"
want_shapes "D10 single-quoted endpoint"     "gh api '$EP' -f \"title=a b\"" "api top"
want_shapes "D32a g\\h"                       'g\h issue create --title x --body y' "create top"
want_shapes "D32b g''h"                       "g''h issue create --title x --body y" "create top"
want_shapes "D32c unquoted echo over-fires"  'echo gh issue create --title x' "create top"
want_shapes "D32d bash -c 'echo gh…' over-fires" "bash -c 'echo gh issue create'" "create shell-c"

# Command positions
want_shapes "D11 pipeline stage"             'printf x | gh issue create --title x --body-file -' "create top"
want_shapes "D12 subshell"                   '( gh issue create --title x --body y )' "create top"
want_shapes "D13 group"                      '{ gh issue create --title x --body y; }' "create top"
want_shapes "D14 if/then"                    'if true; then gh issue create --title x --body y; fi' "create top"
want_shapes "D15 for/do"                     'for i in 1; do gh issue create --title x --body y; done' "create top"
for pre in 'sudo' 'sudo --' 'env A=1' 'env --' 'command' 'timeout -k 5 10' 'nohup' 'nice -5' 'setsid' \
           'flock /tmp/l' 'doppler run --' '/usr/bin/time -v' 'strace -f' 'xargs -r0'; do
  want_shapes "D16 $pre gh" "$pre gh issue create --title x --body y" "create top"
done
want_shapes "D16 find -exec"                 'find /dev/null -maxdepth 0 -exec gh issue create --title x --body y \;' "create top"
want_shapes "D16 /usr/bin/gh"                '/usr/bin/gh issue create --title x --body y' "create top"

# Subcommand forms
want_shapes "D17 gh issue new"               'gh issue new --title x --body y' "create top"
want_shapes "D18a gh issue -R … create"      'gh issue -R jikig-ai/soleur create --title x --body y' "create top"
want_shapes "D18b root --repo"               'gh --repo jikig-ai/soleur issue create --title x --body y' "create top"

# Heredocs
want_shapes "D21 filing after a heredoc opener, same line" $'cat <<\'EOF\' > b.md && gh issue create --title x --body-file b.md\nbody\nEOF' "create top"
want_shapes "D27a unquoted heredoc runs \$(…)" $'cat <<EOF\n$(gh issue create --title x --body y)\nEOF' "create heredoc"
want_shapes "D27b two heredocs on one line" $'cat <<A <<\'B\'\n$(gh issue create --title x --body y)\nA\n$(gh issue create --title q)\nB' "create heredoc"

# Multiple filings and scope
want_shapes "D29 top + bash -c"              "gh issue create --title a --body b$J; bash -c \"gh issue create --title x --body y\"" "create top,create shell-c"
want_shapes "D30 create && api"              "gh issue create --title a --body b$J && gh api $EP -X POST -f title=x" "create top,api top"
want_shapes "D43 | tee is a separator"       'gh issue create --title x --body y --milestone M | tee --label meta/machinery' "create top"
want_shapes "D50a repositories/<id>"         'gh api repositories/1143547205/issues -X POST -f title=x' "api top"
want_shapes "D50b .. segment"                'gh api repos/jikig-ai/soleur/labels/../issues -X POST -f title=x' "api top"
want_shapes "D50c \"\$B/issues\""            'B=repos/jikig-ai/soleur; gh api "$B/issues" -X POST -f title=x' "api top"
want_shapes "D54 \$E-X POST in \$(…)"        "X=\$(gh api $EP \$E-X POST -f body=y)" "api subst"

# Exact fields (Guard 2: a filing's exits come from its OWN argv)
want_lex "D24 --repo of another command is not this filing's" \
  'gh issue list --repo cli/cli && gh issue create --title x --body y' \
  'F create top head=gh issue create|body=y|vis=1'
want_lex "D25 --milestone of another command is not this filing's" \
  'gh issue list --milestone x && gh issue create --title x --body y --label meta/machinery' \
  'F create top head=gh issue create|label=meta/machinery|body=y|vis=1'
want_lex "D26 --label of another command is not this filing's" \
  "gh issue list --label meta/machinery && gh api $EP -X POST -f title=x" \
  "F api top head=gh api $EP|vis=1"
want_lex "D35 bash -c body is the literal body" \
  'echo "User-Impact: docs page Fix-Size: 200 lines / 5 files"; bash -c "gh issue create --title x --body y --milestone M"' \
  'F create shell-c head=gh issue create|milestone=1|body=y'
want_lex "D36 -mx as a --title VALUE is not a milestone" \
  'gh issue create --title -mx --body y --label meta/machinery' \
  'F create top head=gh issue create|label=meta/machinery|body=y|vis=1'
want_lex "D37 --label=… as a --body VALUE is not a label" \
  'gh issue create --title x --body --label=meta/machinery --milestone M' \
  'F create top head=gh issue create|milestone=1|body=--label=meta/machinery|vis=1'
want_lex "D38 a \$-valued --repo stays verbatim" \
  'gh issue create --repo "$OWNER/soleur" --title x --body y' \
  'F create top head=gh issue create|repo=$OWNER/soleur|body=y|vis=1'
want_lex "D40 bare \$EP endpoint" \
  'EP=repos/jikig-ai/soleur/issues; gh api "$EP" -X POST -f title=x' \
  'F api top head=gh api $EP|vis=1'
want_lex "D44 a \$B body with no assignment in view has an empty corpus" \
  'echo "Mandated-By: wg-x" >/dev/null; gh issue create --title x --body "$B" -m M' \
  'F create top head=gh issue create|milestone=1|body=|vis=1'
want_lex "D45 find -exec cut at \\;" \
  'find /dev/null -maxdepth 0 -exec gh issue create --title x --body y -m M \; -exec echo --label meta/machinery \;' \
  'F create top head=gh issue create|milestone=1|body=y|vis=1'
want_lex "D46 the LAST --body wins" \
  'gh issue create --title x --body "Mandated-By: wg-x" --body y -m M' \
  'F create top head=gh issue create|milestone=1|body=y|vis=1'
want_lex "D47 api body=@file is a body file" \
  "gh api $EP -f title=x -F 'body=@/nonexistent-soleur/j Mandated-By: wg-x'" \
  "F api top head=gh api $EP|bodyfile=/nonexistent-soleur/j Mandated-By: wg-x|vis=1"
want_lex "D48a labels[]= in a create --title is not a label" \
  "gh issue create --title 'labels[]=meta/machinery' --body y -m M" \
  'F create top head=gh issue create|milestone=1|body=y|vis=1'
want_lex "D48b create -F labels[]= is a body file" \
  "gh issue create --title x -F 'labels[]=meta/machinery' -m M" \
  'F create top head=gh issue create|milestone=1|bodyfile=labels[]=meta/machinery|vis=1'
want_lex "D49a -R owner is lowercased" \
  'gh issue create -R JIKIG-AI/soleur --title x --body y' \
  'F create top head=gh issue create|repo=jikig-ai/soleur|body=y|vis=1'
want_lex "D49b -R host prefix stripped" \
  'gh issue create -R github.com/jikig-ai/soleur --title x --body y' \
  'F create top head=gh issue create|repo=jikig-ai/soleur|body=y|vis=1'
want_lex "D49c -R URL stripped" \
  'gh issue create -R https://github.com/jikig-ai/soleur --title x --body y' \
  'F create top head=gh issue create|repo=jikig-ai/soleur|body=y|vis=1'
want_lex "api labels[]= field is a label, --input is recorded" \
  "gh api $EP --input b.json -f 'labels[]=meta/machinery'" \
  "F api top head=gh api $EP|label=meta/machinery|input=1|vis=1"
want_lex "the api head is cut at ? and #" \
  "gh api 'repos/o/r/issues?x=1#f' -X POST -f title=x" \
  'F api top head=gh api repos/o/r/issues|vis=1'
want_lex "-mX attached milestone and -l=… label" \
  'gh issue create -mM -l=meta/machinery --title x' \
  'F create top head=gh issue create|milestone=1|label=meta/machinery|vis=1'

# Must-PASS prose (PR3): exit 0, OK, no filing.
BODY_HOSTILE=$'fix: it\'s done, see 1) and an unclosed ( plus `code` and a literal $( and a " quote'
want_prose "P1 commit <<'EOF' in \$(…)"  $'git commit -m "$(cat <<\'EOF\'\n'"$BODY_HOSTILE"$'\nEOF\n)"'
want_prose "P2 commit <<\"EOF\""         $'git commit -m "$(cat <<"EOF"\n'"$BODY_HOSTILE"$'\nEOF\n)"'
want_prose "P3 commit <<\\EOF"           $'git commit -m "$(cat <<\\EOF\n'"$BODY_HOSTILE"$'\nEOF\n)"'
want_prose "P4 commit <<-'EOF' + tab"    $'git commit -m "$(cat <<-\'EOF\'\n'"$BODY_HOSTILE"$'\n\tEOF\n)"'
want_prose "P5 commit -F - heredoc body starts with a filing" $'git commit -F - <<\'EOF\'\ngh issue create --title x --body y\nEOF'
want_prose "P6 heredoc body lines are data" $'git commit -m "$(cat <<\'EOF\'\ngh issue create --title x --body y\n$(gh issue create --title z)\nEOF\n)"'
want_prose "P7a single-quoted ;"          "echo 'done; gh issue create --title x --body y'"
want_prose "P7b double-quoted ;"          'echo "a; gh issue create --title x"'
want_prose "P8 \${…} text is not a script" 'echo "${M:-a; gh issue create --title x}"'
want_prose "P9 comment hides \$(…)"      'echo x # $(gh issue create --title x)'
want_prose "P11 commit message mentions it" 'git commit -m "fix(hooks): don'"'"'t run gh issue create (#9089)"'
want_prose "P13a quoted echo"             'echo "gh issue create --title x"'
want_prose "P13b grep pattern"            'grep -n "gh issue create" notes.md'
want_prose "P13c pr title"                'gh pr create --title "gh issue create" --body x'
want_prose "P13d printf to file"          "printf '%s\n' 'gh issue create --title x' > notes.md"
want_prose "P17 --jq program"             $'gh issue list --json title --jq \'.[] | "it\'\\\'\'s"\''
want_prose "P18 list | xargs label"       "gh api \"$EP?labels=x\" --jq '.[].number' | xargs -I{} gh api -X POST $EP/{}/labels -f 'labels[]=y'"
want_prose "P19 for-loop label"           "for n in \$(gh api \"$EP?labels=x\" --jq '.[].number'); do gh api -X POST $EP/\$n/labels -f 'labels[]=y'; done"
want_prose "P20 {owner} GET"              'gh api repos/{owner}/{repo}/issues --jq length'
want_prose "case pattern ) inside \$(…)"  'x=$(case a in a) echo ok ;; esac)'
want_prose "[[ =~ (a|b) ]] lexes"         '[[ $s =~ ^(x|y)$ ]] && echo y'
want_prose "<<< here-string is a redirection" 'grep -q x <<<"gh issue create --title x"'
want_prose "2>&1 and >&2 are not separators" 'gh issue list 2>&1 >&2 | head -1'

# Filings that pass (the verdict is guardrails.test.sh's; here: they are seen)
want_lex "P10 --body \"\$BODY\" reads the heredoc bound to BODY" \
  $'BODY=$(cat <<\'EOF\'\nUser-Impact: the docs page\nFix-Size: 200 lines / 5 files\nEOF\n); gh issue create --title x --body "$BODY" --milestone "Post-MVP / Later"' \
  $'F create top head=gh issue create|milestone=1|body=User-Impact: the docs page\nFix-Size: 200 lines / 5 files\n|vis=1'
# ... and never another command's text (security #5): the echo's Mandated-By
# is not in the corpus.
want_lex "P10b the body corpus is the variable's value, never another command's args" \
  $'BODY=$(cat <<\'EOF\'\nUser-Impact: the docs page\nEOF\n); echo Mandated-By: wg-x; gh issue create --title x --body "$BODY" -m M' \
  $'F create top head=gh issue create|milestone=1|body=User-Impact: the docs page\n|vis=1'
want_shapes "P14a justified in \$(…)"    "URL=\$(gh issue create --title x --body y$J)" "create subst"
want_shapes "P14b justified in bash -c"  "bash -c \"gh issue create --title x --body y$K\"" "create shell-c"
want_lex "P15 literal external --repo" \
  'gh issue create --repo cli/cli --title x --body y' \
  'F create top head=gh issue create|repo=cli/cli|body=y|vis=1'
want_lex "P21 two --label flags" \
  "gh issue create --title x --body y --label type/bug$J" \
  'F create top head=gh issue create|milestone=1|label=type/bug|label=meta/machinery|body=y|vis=1'

# Review round (#9089): one lexer row per reproduced grammar/field finding.
want_lex "R-CR \\r is a word character (no forged milestone)" \
  $'gh issue create --title x --label meta/machinery --body=x\r-mPost' \
  $'F create top head=gh issue create|label=meta/machinery|body=x\r-mPost|vis=1'
want_prose "R-FF a form feed is a word character" $'echo a\fb'
want_shapes "R-HDQ a newline inside \$(…) does not drain an outer heredoc" \
  $'cat <<\'EOF\'; X="$(:\ngh issue create --title x --body y\nEOF\n)"\nEOF' "create subst"
want_shapes "R-ARITH (( … << … )) is a shift" \
  $'(( x = 1 << y ))\ntrue | gh issue create --title x --body y' "create top"
want_shapes "R-ARITH-FOR for (( … << … )) is a shift" \
  $'for (( i = 1 << 2; i < 9; i++ )); do gh issue create --title x --body y; done' "create top"
want_shapes "R-SUBSHELL ((cmd) ) is two subshells, not arithmetic" \
  '((gh issue create --title x --body y) )' "create top"
want_shapes "R-SUBSHELL2 \$( (cmd) ) is a subshell inside \$(…)" \
  'X=$( (gh issue create --title x --body y) )' "create subst"
want_shapes "R-CASE a case pattern ) does not close \$(…)" \
  'x="$(case $y in a|b) gh issue create --title t;; *) :;; esac)"' "create subst"
want_prose "R-CASE-PROSE case patterns are not commands" \
  'case "$x" in gh|issue) echo a ;; create) echo b ;; esac'
want_shapes "R-FUNSUB \${ cmd; } is a script" 'X=${ gh issue create --title x --body y; }' "create subst"
want_shapes "R-FUNSUB2 \${| cmd; } is a script" 'X=${| gh issue create --title x --body y; }' "create subst"
want_shapes "R-OC bash -oc takes its o's value first" \
  "bash -oc pipefail 'gh issue create --title x --body y'" "create shell-c"
want_lex "R-ANSI \$'…' is decoded before eval splits it" \
  "eval \$'gh issue create --title x --body y -l meta/machinery \\n -m M'" \
  'F create eval head=gh issue create|label=meta/machinery|body=y'
want_lex "R-BTDQ \\\" inside backticks in \"…\" is a quote" \
  'X="`gh issue create --title \"a --label meta/machinery \" --milestone M`"' \
  'F create backtick head=gh issue create|milestone=1'
want_lex "R-FIND a later -exec is outside the filing" \
  'find /dev/null -exec timeout 9 gh issue create --title x --body y \; -exec echo -m M -l meta/machinery \;' \
  'F create top head=gh issue create|body=y|vis=1'
want_lex "R-SCP git@host:owner/repo normalizes to OWNER/REPO" \
  'gh issue create -R git@github.com:JIKIG-AI/soleur.git --title t --body x' \
  'F create top head=gh issue create|repo=jikig-ai/soleur|body=x|vis=1'
want_lex "R-EMPTYM an empty milestone value is no milestone" \
  'gh issue create --title x --body y --milestone "" --label meta/machinery' \
  'F create top head=gh issue create|label=meta/machinery|body=y|vis=1'
want_lex "R-TRUE substitution text is not body corpus" \
  'gh issue create --title x -m M --body "$(true Mandated-By: hr-foo)"' \
  'F create top head=gh issue create|milestone=1|body=|vis=1'
want_lex "R-RAWAT -f body=@x is a literal body; -F body=@x is a body file" \
  "gh api repos/o/r/issues -f title=x -f 'body=@/a' -F 'body=@/b'" \
  'F api top head=gh api repos/o/r/issues|bodyfile=/b|vis=1'
want_lex "R-HDBODY --body \"\$(cat <<'EOF' …)\" is the heredoc text, once" \
  $'gh issue create --title x -m M --body "$(cat <<\'B\'\nUser-Impact: login page\nFix-Size: 3 lines / 1 file\nB\n)"' \
  $'F create top head=gh issue create|milestone=1|body=User-Impact: login page\nFix-Size: 3 lines / 1 file\n|vis=1'
want_lex "R-READ read … B <<EOF binds the heredoc to \$B" \
  $'read -r -d \'\' B <<\'EOF\'\nUser-Impact: docs page\nEOF\ngh issue create --title x --body "$B" -m M' \
  $'F create top head=gh issue create|milestone=1|body=User-Impact: docs page\n|vis=1'
want_shapes "R-DUP two identical substitutions are two filings" \
  'a=$(gh api repos/o/r/issues -f title=x); b=$(gh api repos/o/r/issues -f title=x)' "api subst,api subst"
want_lex "R-VIS a filing inside quotes is invisible to the floor" \
  'X="$(gh issue create --title x -m M)"' 'F create subst head=gh issue create|milestone=1'
want_lex "R-VIS2 an unquoted substitution is visible to the floor" \
  'X=$(gh issue create --title x -m M)' 'F create subst head=gh issue create|milestone=1|vis=1'
want_shapes "R-HDCTX a \$(…) in an unquoted heredoc reports the heredoc" \
  $'cat <<EOF\n$(gh issue create --title x)\nEOF' "create heredoc"
want_prose "R-PULLS a \$-valued --jq on a pulls POST is no issues endpoint" \
  'gh api repos/o/r/pulls -X POST -f title=x --jq "$Q"'
_pad="$(printf '/repos/%.0s' $(seq 1 20000))"
want_shapes "R-PAD 140 KB of /repos/ is linear, not an alarm" \
  "gh api -H \"X-Pad: ${_pad}!\" \"\$EP\" -X POST -f title=x" "api top"
_many="$(printf 'echo gh issue create -m M --label meta/machinery; %.0s' $(seq 1 40))"
want_fail "R-RECORDS more than 32 filings is a bound, not 32 forks of the gate" "$_many" 3 records

# ---------------------------------------------------------------------------
# 3. Failure exits and bounds (asserted by exit code and bound=<cause>).
bound_of() { printf '%s' "$1" | perl "$PL" 2>&1 >/dev/null | sed -n 's/^bound=\([a-z0-9]*\).*/\1/p' | head -1; }
rc_of()    { printf '%s' "$1" | perl "$PL" >/dev/null 2>&1; echo "$?"; }
want_fail() {
  local label="$1" cmd="$2" rc="$3" cause="$4" g_rc g_cause g_out
  g_rc="$(rc_of "$cmd")"; g_cause="$(bound_of "$cmd")"; g_out="$(lex "$cmd")"
  if [[ "$g_rc" == "$rc" && "$g_cause" == "$cause" && "$g_out" == "E $cause"$'\n'"RC $rc" ]]; then pass "$label"
  else fail "$label" "want rc=$rc bound=$cause stream=E $cause; got rc=$g_rc bound=$g_cause stream=${g_out//$'\n'/ ⏎ }"; fi
}
# INSTRUMENT SELF-TEST for the verdict-owning helpers: each must report a
# known-wrong expectation as a FAIL, or a gutted helper (always pass) passes
# every row and the floor alike. Unwound afterwards; reported via printf+exit.
_hc_p=$PASS; _hc_f=$FAIL; _hc_t=$TOTAL
want_lex    "ctl" 'echo x' 'F create top head=nope' >/dev/null
want_prose  "ctl" 'gh issue create --title x' >/dev/null
want_shapes "ctl" 'echo x' 'create top' >/dev/null
want_fail   "ctl" 'echo x' 2 exit2 >/dev/null
want_prose  "ctl" 'echo x' >/dev/null
if (( FAIL != _hc_f + 4 || PASS != _hc_p + 1 )); then
  printf 'INSTRUMENT: want_* helpers did not report 4 known FAILs and 1 known PASS (PASS %s->%s FAIL %s->%s)\n' \
    "$_hc_p" "$PASS" "$_hc_f" "$FAIL" >&2
  exit 1
fi
PASS=$_hc_p; FAIL=$_hc_f; TOTAL=$_hc_t

want_fail "F2a unbalanced '"              "gh issue create --title 'x"            2 exit2
want_fail "F2b unbalanced \""             'gh issue create --title "x'            2 exit2
want_fail "F2c unterminated \$("          'X=$(gh issue create --title x'         2 exit2
want_fail "F2d unterminated backtick"     'echo `gh issue create'                 2 exit2
want_fail "F2e missing heredoc delimiter" 'cat <<'                                2 exit2
_nul_rc="$(printf 'gh issue create\0x' | perl "$PL" >/dev/null 2>&1; echo $?)"
if [[ "$_nul_rc" == 2 ]]; then pass "F2f NUL byte exits 2"; else fail "F2f NUL byte exits 2" "rc=$_nul_rc"; fi
_deep='gh issue create --title x'
for _ in $(seq 1 20); do _deep="\$($_deep)"; done
want_fail "AC6 20-deep \$(…) trips the depth bound" ": $_deep" 3 depth
_pad="$(printf 'true %.0s' $(seq 1 8000))"
_ev="$(printf 'eval %.0s' $(seq 1 15))"
want_fail "AC6 15 re-lexed eval strings trip the character budget" "$_ev$_pad" 3 budget
_nest='gh issue create --title x'
for _ in $(seq 1 7); do _nest="bash -c \"\$($_nest)\""; done
_nest_rc="$(rc_of "$_nest")"
if [[ "$_nest_rc" == 0 ]]; then pass "AC6 memoized nested bash -c \"\$(…)\" stays under budget"; else fail "AC6 memoized nested bash -c stays under budget" "rc=$_nest_rc bound=$(bound_of "$_nest")"; fi
_al_out="$( { sleep 3; printf 'gh issue create'; } | perl "$PL" 2>&1 >/dev/null; echo "rc=$?")"
if [[ "$_al_out" == *"bound=alarm"* && "$_al_out" == *"rc=3" ]]; then pass "AC6 the alarm exits 3 with bound=alarm"; else fail "AC6 the alarm exits 3 with bound=alarm" "$_al_out"; fi

# ---------------------------------------------------------------------------
# 4. Flag-table staleness. gh's own help lists the value-taking flags as the
#    ones with a type word after the names. Compared only against the gh
#    version the tables are PINNED to: a newer gh on a CI runner must not turn
#    every unrelated PR red, and an absent gh must not trip the floor. Skipped
#    rows are counted in SKIPPED, which the floor adds back.
SKIPPED=0
_pinned_gh="$(perl "$PL" --tables | sed -n 's/^gh //p')"
_have_gh="$(command -v gh >/dev/null 2>&1 && gh --version 2>/dev/null | awk 'NR==1{print $3}')"
if [[ -n "$_have_gh" && "$_have_gh" == "$_pinned_gh" ]]; then
  gh_vals() {
    gh help "$@" 2>/dev/null | awk '/^FLAGS/{f=1;next} /^[A-Z]/{f=0} f' \
      | perl -ne 'if (/^\s+(?:(-\w), )?(--[\w-]+)\s(\S+)/ && $3 !~ /^[A-Z]/) { print "$1\n" if $1; print "$2\n" }' | sort -u
  }
  tables="$(perl "$PL" --tables)"
  pl_create="$(sed -n 's/^create-val //p' <<<"$tables" | tr ' ' '\n' | grep -vxE -- '-R|--repo' | sort -u)"
  pl_api="$(sed -n 's/^api-val //p' <<<"$tables" | tr ' ' '\n' | sort -u)"
  gh_create="$(gh_vals issue create)"
  gh_api="$(gh_vals api)"
  if [[ "$pl_create" == "$gh_create" ]]; then pass "flag tables: gh issue create value flags match gh $(gh --version | awk 'NR==1{print $3}')"
  else fail "flag tables: gh issue create value flags drifted" "$(diff <(echo "$pl_create") <(echo "$gh_create"))"; fi
  if [[ "$pl_api" == "$gh_api" ]]; then pass "flag tables: gh api value flags match"
  else fail "flag tables: gh api value flags drifted" "$(diff <(echo "$pl_api") <(echo "$gh_api"))"; fi
else
  SKIPPED=$((SKIPPED + 2))
  echo "SKIP: flag tables (installed gh '${_have_gh:-none}' is not the pinned ${_pinned_gh}; re-pin after checking \`gh help issue create\` and \`gh help api\`)"
fi

# ---------------------------------------------------------------------------
# 5. The discoverability probe.
_probe_out="$(bash "${BASH_SOURCE[0]}" --probe)"
if [[ "$_probe_out" == "PROBE=create" ]]; then pass "probe prints PROBE=create"; else fail "probe prints PROBE=create" "$_probe_out"; fi

# ---------------------------------------------------------------------------
# Floor: a literal, bumped in the same commit as the rows. Reported with
# printf + exit, never through fail().
MIN_ASSERTIONS=263
if (( TOTAL + SKIPPED < MIN_ASSERTIONS )); then
  printf 'FLOOR: only %s assertions ran, expected at least %s\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
