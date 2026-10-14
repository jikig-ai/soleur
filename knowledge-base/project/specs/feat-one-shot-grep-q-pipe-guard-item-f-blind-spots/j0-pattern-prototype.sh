#!/usr/bin/env bash
# Item F plan-time prototype (J0b): the widened PATTERN_V2, POSIX ERE only, compared with the shipped one.
# Read-only. Run from anywhere inside the checkout:  bash j0-pattern-prototype.sh
# It prints the live-tree delta (shipped pattern vs widened pattern over the guard's own sweep population) and a fixture table.
# The widened text is the STARTING POINT of Phase 1 in the plan, not the authority: the guard's own fixtures are.
set -u
cd "$(git rev-parse --show-toplevel)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
OLD='(^|[^|])\|&?[[:space:]]*(\{[[:space:]]+|\([[:space:]]*)?((command|builtin|exec|env|nice|stdbuf[[:space:]]+-[a-zA-Z]+|timeout[[:space:]]+[0-9a-z.]+)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(\\|/[^[:space:]]*/)?(e|f)?grep([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?|-[efABCm][[:space:]]+[^[:space:]]+))*[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
# TOK: one shell word, quote-aware, so a quoted pattern that contains " -q " is consumed whole and never read as a flag.
TOK='('"'"'[^'"'"']*'"'"'|"[^"]*"|[^[:space:]'"'"'"|;&)}]+)+'
LEAD='(^|[^|])\|&?[[:space:]]*(\{[[:space:]]+|\([[:space:]]*)?'
WRAPW='(command|builtin|exec|env|nice|stdbuf|timeout|sudo|doas|time|nohup|setsid|xargs|ionice)'
WRAP="(${WRAPW}([[:space:]]+${TOK}){0,4}[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*"
BIN='((\\|/[^[:space:]]*/)?(e|f|z|ze)?grep|(\\|/[^[:space:]]*/)?(rg|ag|ugrep|pcregrep)|"?\$\{?[A-Za-z_]*[Gg][Rr][Ee][Pp][A-Za-z_]*(:-[^}]*)?\}?"?)'
FLAG='([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?|-[efABCmdD][[:space:]]+[^[:space:]]+))*'
# At most ONE bare operand between the flags: GNU grep permutes (`grep P -q`), and a wider run reads a quoted pipe in a test string as code (measured: +24 then +5 lines on this tree).
ARG="${FLAG}([[:space:]]+${TOK})?${FLAG}"
EARLY='[[:space:]]+(-[A-Za-z0-9]*[qm][A-Za-z0-9]*|--(q[a-z]*|si[a-z]*|max(-c[a-z]*)?)(=[^[:space:]]*)?)([[:space:]]|$|[;&)}|])'
# SHC: the reader inside `sh -c '...'` / `bash -lc "..."` (its own alternative: the quote hides the grep from the main grammar).
SHC='(^|[^|])\|&?[[:space:]]*(ba|da)?sh[[:space:]]+(-[a-z]+[[:space:]]+)*-[a-z]*c[[:space:]]+['"'"'"]([^'"'"'"]*[^[:alnum:]_/.-])?(e|f)?grep([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+(-[A-Za-z0-9]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
NEW="${LEAD}${WRAP}${BIN}${ARG}${EARLY}|${SHC}"
PS=( ':(glob)**/*.sh' ':(glob)**/*.bash' ':(glob)**/*.bats' ':(glob)**/*.yml' ':(glob)**/*.yaml' ':(glob)**/*.tf' ':(glob)**/*.template' ':(glob)**/*.js' ':(exclude)knowledge-base' ':(exclude).claude/hooks/grep-q-pipe-guard.test.sh' )
run() { git -c core.excludesFile=/dev/null grep --no-index --exclude-standard -anE -e "$1" -- "${PS[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE '[[:space:]]#[[:space:]]*sigpipe-demo:[[:space:]]*intentional([[:space:]]|$)' | cut -d: -f1,2 | sort; }
run "$OLD" > "$W/old.hits"; run "$NEW" > "$W/new.hits"
echo "live tree: shipped=$(wc -l < "$W/old.hits") widened=$(wc -l < "$W/new.hits")  (want equal: 0 new hits)"
echo "only in widened:"; comm -13 "$W/old.hits" "$W/new.hits" | head -20
cp "$(dirname "${BASH_SOURCE[0]}")/j0-pattern-fixtures.txt" "$W/fx.txt"
ok=1
while IFS= read -r l; do [[ "$l" == "#"* ]] && continue; k="${l%% *}"; t="${l#* }"; r=0; grep -E -- "$NEW" <<<"$t" >/dev/null || r=$?
  case "$k" in
    BAD)  [[ $r == 0 ]] || { echo "MISS  $t"; ok=0; } ;;
    GOOD) [[ $r == 1 ]] || { echo "FP    $t"; ok=0; } ;;
    KNOWNFP) echo "known false positive (rc $r): $t" ;;
  esac
done < "$W/fx.txt"
echo "fixture table ok=$ok"
