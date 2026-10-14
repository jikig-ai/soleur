#!/usr/bin/env bash
# rtk-grammar-parity.test.sh — the rtk exec-subcommand set lives in ~7 places with no shared
# evaluation path (three input models: lexer token array, pipeline-stage text, /proc argv).
# Per-site unwrap CODE is duplicated by design; the DATA must not drift (#10230). This suite
# EXTRACTS the set from each site and asserts it equals the canonical table —
# parity by extraction, never a shared import: the python oracle in
# destructive-command-guard-hook.test.sh is an independent second implementation, and wiring
# it to the canonical file would make it a copy of what it verifies.
#
# Auto-discovered by the `scripts` group glob in scripts/test-all.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CANON="$REPO_ROOT/plugins/soleur/scripts/lib/ext-filter-grammar.tsv"
GUARD="$REPO_ROOT/plugins/soleur/hooks/destructive-command-guard.sh"
HOOKTEST="$REPO_ROOT/plugins/soleur/test/destructive-command-guard-hook.test.sh"
PKILL="$REPO_ROOT/.claude/hooks/pkill-self-match-guard.sh"
PROC="$REPO_ROOT/plugins/soleur/scripts/lib/proc.sh"
DOC="$REPO_ROOT/plugins/soleur/docs/pages/known-external-tools.md"

echo "=== rtk exec-subcommand grammar parity (extraction vs canonical TSV) ==="
echo ""

assert_file_exists "$CANON" "canonical grammar table exists"
assert_file_exists "$GUARD" "destructive-command-guard.sh exists"
assert_file_exists "$HOOKTEST" "hook test exists"
assert_file_exists "$PKILL" "pkill-self-match-guard.sh exists"
assert_file_exists "$PROC" "proc.sh exists"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

# canonical: the subcommand column of every class=exec row, sorted
want="$(awk -F'\t' '$0 !~ /^#/ && NF >= 3 && $2 == "exec" { print $1 }' "$CANON" | sort | tr '\n' ' ' | sed 's/ $//')"
[[ -n "$want" ]] || { echo "FATAL: canonical TSV yielded no exec subcommands"; exit 3; }
echo "canonical set: $want"
echo ""

# extract: turn any spelling of the alternation (a|b|c, "a", "b", "c") into the sorted set.
# Every extraction is BOUNDED on both edges — a presence-grep of the canonical literal
# passes on `x|run|…` (prepended drift) and `summary|x` (appended drift), which is the
# direction this mechanism exists to catch (TSV header: "upstream added a shape").
# So each site anchors the alternation between non-member delimiters, then strips the
# captured delimiters before norm().
norm() { tr '"|,()' '     ' | tr -s ' ' '\n' | grep -vE '^\s*$' | sort | tr '\n' ' ' | sed 's/ $//'; }
SET='[A-Za-z0-9_|]+'   # any alternation spelling — NOT the canonical literal, so any set drift shows up

# 1. wrap_skip arm in destructive-command-guard.sh — the case item inside the rtk) arm
got="$(sed -n '/^    rtk)  # grammar/,/^    nohup|-p)/p' "$GUARD" \
  | grep -oE "run($SET)\\)" | head -1 | tr -d ')' | norm || true)"
assert_eq "$want" "$got" "wrap_skip rtk arm exec set matches canonical"

# 2. header prose in destructive-command-guard.sh — the parenthesized set
got="$(grep -oE "\\(run($SET)" "$GUARD" | head -1 | tr -d '(' | norm || true)"
assert_eq "$want" "$got" "guard header prose exec set matches canonical"

# 3. python oracle in the hook suite — the tuple inside unwrap()'s rtk arm
got="$(sed -n '/elif name == "rtk":/,/return args\[i:\]/p' "$HOOKTEST" \
  | grep -oE '\("run"(, "[A-Za-z0-9_]+")*\)' | head -1 | norm || true)"
assert_eq "$want" "$got" "python oracle exec set matches canonical (independent impl — extracted, not shared)"

# 4. pkill-self-match-guard.sh stage_word — the exec-subcommand case item
got="$(grep -oE "run($SET)\\) \\(\\( rtk_prev" "$PKILL" | head -1 | sed 's/).*//' | norm || true)"
assert_eq "$want" "$got" "pkill stage_word exec set matches canonical"

# 5. proc.sh wrapper walk — the consuming case arm (anchored past the comment at :76)
got="$(grep -oE "run($SET)\\) i=\\$\\(\\(" "$PROC" | head -1 | sed 's/) i=.*//' | norm || true)"
assert_eq "$want" "$got" "proc.sh walk exec set matches canonical (code arm, not the comment)"

# 6. known-external-tools.md reproduces the canonical table — extract its exec-subcommand line
if [[ -f "$DOC" ]]; then
  got="$(grep -oE "exec subcommands:  run($SET)" "$DOC" | head -1 | sed 's/.*run/run/' | norm || true)"
  assert_eq "$want" "$got" "known-external-tools.md exec set matches canonical"
else
  echo "NOTE: known-external-tools.md absent — doc parity skipped (lands in the docs phase)"
fi

# 7-9. The boundary-prefix fragment's rtk atom (#10248) — SOLEUR_RTK_RE in
# plugins/soleur/scripts/lib/wrapper-boundary.sh restates BOTH the exec set and
# the flag sets; each is asserted against its own canonical TSV class.
WBLIB="$REPO_ROOT/plugins/soleur/scripts/lib/wrapper-boundary.sh"
assert_file_exists "$WBLIB" "wrapper-boundary.sh (shared boundary fragment) exists"
if [[ -f "$WBLIB" ]]; then
  # The inner alternation between `[[:space:]]+(` and `))*'` — non-member
  # delimiters both edges, same discipline as arms 1-6.
  members="$(grep -E "^SOLEUR_RTK_RE=" "$WBLIB" | head -1 \
    | sed -E "s/^SOLEUR_RTK_RE='rtk\(\[\[:space:\]\]\+\(//; s/\)\)\*'.*$//" \
    | tr '|' '\n' | grep -vE '^\s*$')"
  [[ -n "$members" ]] || { echo "FATAL: SOLEUR_RTK_RE extraction yielded no members"; exit 3; }
  # bare-word members are exec subcommands; dash-members are global flags
  # (value-shape suffixes like (=[^[:space:]]+)? normalize to the bare flag).
  frag_exec="$(grep -E '^[a-z]+$' <<<"$members" | sort | tr '\n' ' ' | sed 's/ $//')"
  frag_glob="$(grep -E '^-' <<<"$members" | sed 's/(=.*//' | sort | tr '\n' ' ' | sed 's/ $//')"
  [[ -n "$frag_exec" && -n "$frag_glob" ]] \
    || { echo "FATAL: fragment member split yielded an empty arm (exec='$frag_exec' glob='$frag_glob')"; exit 3; }

  assert_eq "$want" "$frag_exec" "wrapper-boundary SOLEUR_RTK_RE exec set matches canonical"

  tsv_glob="$(awk -F'\t' '$0 !~ /^#/ && NF >= 3 && $2 == "flag-global" { print $1 }' "$CANON" | sort | tr '\n' ' ' | sed 's/ $//')"
  [[ -n "$tsv_glob" ]] || { echo "FATAL: canonical TSV yielded no flag-global rows"; exit 3; }
  assert_eq "$tsv_glob" "$frag_glob" "wrapper-boundary SOLEUR_RTK_RE global-flag set matches canonical flag-global rows"

  # Partition completeness: every member must land in exactly one asserted set —
  # a member matching neither ^[a-z]+$ (exec) nor ^- (flag) would drift untested.
  frag_all="$(grep -vE '^\s*$' <<<"$members" | sed 's/(=.*//' | sort | tr '\n' ' ' | sed 's/ $//')"
  frag_union="$(printf '%s\n%s\n' "$frag_exec" "$frag_glob" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "$frag_all" "$frag_union" "fragment member partition is complete (exec ∪ globals == all members)"

  # flag-string flags (-c/--command/--shell) are the exclusion pin: the boundary
  # atom must NOT admit them (opaque-payload class), so zero members overlap.
  tsv_str="$(awk -F'\t' '$0 !~ /^#/ && NF >= 3 && $2 == "flag-string" { print $1 }' "$CANON" | sort)"
  [[ -n "$tsv_str" ]] || { echo "FATAL: canonical TSV yielded no flag-string rows"; exit 3; }
  overlap="$(comm -12 <(sort <<<"$tsv_str") <(grep -E '^-' <<<"$members" | sed 's/(=.*//' | sort) | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "" "$overlap" "wrapper-boundary SOLEUR_RTK_RE admits no flag-string members (opaque-payload exclusion)"
fi

print_results
