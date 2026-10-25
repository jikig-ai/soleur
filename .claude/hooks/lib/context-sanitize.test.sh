#!/usr/bin/env bash
# Tests for .claude/hooks/lib/context-sanitize.sh (issue #10395).
#
# Byte-contract fixtures only: pipe strings through the three variants, no git
# fixtures. Carries two guards from the plan: copy parity (cmp) and the
# context-strip drift sentinel (enumeration + disposition list).
# No `set -e`: accumulate-then-exit suite; every check is captured so a failing
# call cannot abort before it is reported.

set -uo pipefail

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_LIB="$SCRIPT_DIR/context-sanitize.sh"
PLUGIN_LIB="$SCRIPT_DIR/../../../plugins/soleur/scripts/lib/context-sanitize.sh"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd -P)"

FAILS=0
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILS=$((FAILS+1)); }
pass() { printf 'ok: %s\n' "$1"; }

# --- byte-contract fixtures ------------------------------------------------

. "$REPO_LIB" || { printf 'FATAL: cannot source %s\n' "$REPO_LIB" >&2; exit 2; }

# strip-all: C0, DEL, ESC, NEL, LS, PS removed; printable survives.
out=$(printf 'a\x7fb\xe2\x80\xa8c\xc2\x85d\x1be\xe2\x80\xa9f' | soleur_ctx_sanitize)
[ "$out" = "abcdef" ] && pass "strip-all removes DEL/LS/PS/NEL/ESC" || fail "strip-all: got $(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')"

# keep-lines: TAB+LF survive; DEL/LS/PS/NEL removed.
out=$(printf 'a\tb\nc\x7fd\xc2\x85e\xe2\x80\xa8f' | soleur_ctx_sanitize_lines)
[ "$out" = "$(printf 'a\tb\ncdef')" ] && pass "keep-lines strips DEL/NEL/LS keeps TAB+LF" || fail "keep-lines: got $(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')"
grep -q '7f' <<<"$(printf 'a\tb\nc\x7fd\xc2\x85e\xe2\x80\xa8f' | soleur_ctx_sanitize_lines | od -An -tx1)" && fail "keep-lines passed DEL"
grep -q 'e2' <<<"$(printf 'x\xe2\x80\xa8y' | soleur_ctx_sanitize_lines | od -An -tx1)" && fail "keep-lines passed LS"
grep -q 'e2' <<<"$(printf 'x\xe2\x80\xa9y' | soleur_ctx_sanitize_lines | od -An -tx1)" && fail "keep-lines passed PS"
grep -q 'c2' <<<"$(printf 'x\xc2\x85y' | soleur_ctx_sanitize_lines | od -An -tx1)" && fail "keep-lines passed NEL"

# newline-only: LF survives, TAB stripped.
out=$(printf 'a\tb\nc\td' | soleur_ctx_sanitize_nl)
[ "$out" = "$(printf 'ab\ncd')" ] && pass "newline-only strips TAB keeps LF" || fail "newline-only: got $(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')"
grep -qE '7f|e2' <<<"$(printf 'x\x7fy\xe2\x80\xa8z' | soleur_ctx_sanitize_nl | od -An -tx1)" && fail "newline-only passed DEL/LS"

# --- ANSI-C quoting pin (BSD sed silently no-ops on bare '\xHH') ------------

grep -q "\$'s/" "$REPO_LIB"   || fail "repo lib: sed patterns lack \$'…' ANSI-C quoting"
grep -q "\$'s/" "$PLUGIN_LIB" || fail "plugin lib: sed patterns lack \$'…' ANSI-C quoting"
pass "ANSI-C quoting pinned on both copies"

# --- Guard 2: copy parity ---------------------------------------------------

[ -f "$REPO_LIB" ]   || fail "repo lib is not a regular file"
[ -f "$PLUGIN_LIB" ] || fail "plugin lib is not a regular file"
cmp -s "$REPO_LIB" "$PLUGIN_LIB" && pass "cmp parity" || fail "lib copies diverged (cmp non-zero)"

# --- Guard 1: drift sentinel ------------------------------------------------
# Every production `tr -d '\000-…` / `tr -d '[:cntrl:]'` site outside the lib is
# either an adopted site (its declare -F fallback legitimately carries the
# pre-change strip set) or a recorded disposition. A NEW raw strip fails here.
# The lib's own function defs match the pattern, so a zero-hit enumeration is
# vacuous (floor assertion below).

DISPOSITIONS=$(cat <<'EOF'
.claude/hooks/lib/context-sanitize.sh|lib (floor)
plugins/soleur/scripts/lib/context-sanitize.sh|lib (floor)
.claude/hooks/bare-root-cwd-guard.sh|adopted — declare -F fallback only
.claude/hooks/session-rules-loader.sh|adopted — declare -F fallback only
.claude/hooks/agent-token-tee.sh|adopted — declare -F fallback only
.claude/hooks/pre-merge-rebase.sh|adopted — declare -F fallback only
.claude/hooks/prod-write-defer-gate.sh|adopted — declare -F fallback only
.claude/hooks/monitor-arm-recorder.sh|adopted — declare -F fallback only (DESC upgrade to strip-all)
.claude/hooks/ship-kb-archive-gate.sh|adopted — declare -F fallback only
.claude/hooks/cla-signed-author-gate.sh|adopted — declare -F fallback only
.claude/hooks/ship-unpushed-commits-gate.sh|adopted — declare -F fallback only
plugins/soleur/hooks/bare-root-cwd-guard.sh|adopted — declare -F fallback only (plugin arm, #10392)
plugins/soleur/hooks/operator-stage-approval.sh|adopted — declare -F fallback only
plugins/soleur/scripts/run-in-pid-namespace.sh|adopted — declare -F fallback only
plugins/soleur/scripts/resolve-regenerable-conflicts.sh|adopted — declare -F fallback only
plugins/soleur/scripts/domain-model-drift.sh|adopted — declare -F fallback only
plugins/soleur/skills/ship/scripts/battery-owed.sh|adopted — declare -F fallback only
plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh|adopted — declare -F fallback only
plugins/soleur/skills/review/scripts/fix-round-seats.sh|adopted — declare -F fallback only (census-missed site, same class)
plugins/soleur/skills/ship/scripts/hold-gate-eval.sh|superset — strips strictly more (cntrl + C1 + wider e2 classes + BOM); leave as-is
plugins/soleur/skills/preflight/SKILL.md|doc snippet — canonical form, recorded
plugins/soleur/skills/preflight/references/check-13-founder-check.md|doc snippet — canonical form, recorded
plugins/soleur/scripts/merge-effect-class.sh|measurement only — compares the byte count with and without NUL to refuse a NUL-bearing path list; never emits sanitized output
EOF
)

cd "$REPO_ROOT" || { printf 'FATAL: cannot cd to repo root\n' >&2; exit 2; }
hits=$(grep -rlnE "tr -d ('\\\\0|'\[:cntrl:\])" .claude/hooks/ plugins/soleur/ 2>/dev/null | grep -v '\.test\.sh$' | sort)
hit_count=$(printf '%s\n' "$hits" | grep -c .)
[ "$hit_count" -ge 2 ] || fail "sentinel enumeration vacuous: $hit_count hits (lib defs alone should match)"

while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! grep -qF "$f|" <<<"$DISPOSITIONS"; then
    fail "undispositioned strip site: $f — adopt or add a disposition row"
  fi
done <<< "$hits"

# Every listed disposition names a path that exists (renames must update here).
while IFS='|' read -r f why; do
  [ -z "$f" ] && continue
  [ -e "$REPO_ROOT/$f" ] || fail "disposition names missing path: $f ($why)"
done <<< "$DISPOSITIONS"

[ "$FAILS" -eq 0 ] && pass "drift sentinel: $hit_count sites, all dispositioned"

if [ "$FAILS" -eq 0 ]; then
  echo "context-sanitize.test.sh: PASS"
  exit 0
else
  echo "context-sanitize.test.sh: FAIL ($FAILS failures)"
  exit 1
fi
