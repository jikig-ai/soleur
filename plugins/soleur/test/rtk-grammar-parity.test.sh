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

# extract: turn any spelling of the alternation (a|b|c, "a", "b", "c") into the sorted set
norm() { tr '"|,()' '     ' | tr -s ' ' '\n' | grep -vE '^\s*$' | sort | tr '\n' ' ' | sed 's/ $//'; }

# 1. wrap_skip arm in destructive-command-guard.sh — the case item inside the rtk) arm
got="$(sed -n '/^    rtk)  # grammar/,/^    nohup|-p)/p' "$GUARD" \
  | grep -oE 'run\|err\|test\|proxy\|bypass\|summary([^|a-zA-Z]|$)' | head -1 | norm || true)"
assert_eq "$want" "$got" "wrap_skip rtk arm exec set matches canonical"

# 2. header prose in destructive-command-guard.sh — the parenthesized set
got="$(grep -oE '\(run\|err\|test\|proxy\|bypass\|summary([^|a-zA-Z]|$)' "$GUARD" | head -1 | norm || true)"
assert_eq "$want" "$got" "guard header prose exec set matches canonical"

# 3. python oracle in the hook suite — the tuple inside unwrap()'s rtk arm
got="$(sed -n '/elif name == "rtk":/,/return args\[i:\]/p' "$HOOKTEST" \
  | grep -oE '\("run", "err", "test", "proxy", "bypass", "summary"\)' | head -1 | norm || true)"
assert_eq "$want" "$got" "python oracle exec set matches canonical (independent impl — extracted, not shared)"

# 4. pkill-self-match-guard.sh stage_word — the exec-subcommand case item
got="$(grep -oE 'run\|err\|test\|proxy\|bypass\|summary\) \(\(' "$PKILL" | head -1 | norm || true)"
assert_eq "$want" "$got" "pkill stage_word exec set matches canonical"

# 5. proc.sh wrapper walk — the exec-subcommand consumption case
got="$(grep -oE 'run\|err\|test\|proxy\|bypass\|summary\)' "$PROC" | head -1 | norm || true)"
assert_eq "$want" "$got" "proc.sh walk exec set matches canonical"

# 6. known-external-tools.md reproduces the canonical table — extract its exec-subcommand line
if [[ -f "$DOC" ]]; then
  got="$(grep -oE 'run\|err\|test\|proxy\|bypass\|summary' "$DOC" | head -1 | norm || true)"
  assert_eq "$want" "$got" "known-external-tools.md exec set matches canonical"
else
  echo "NOTE: known-external-tools.md absent — doc parity skipped (lands in the docs phase)"
fi

print_results
