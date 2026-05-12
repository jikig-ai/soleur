# shellcheck shell=bash
# Shared computation of the AGENTS.md "always-loaded" payload byte total.
#
# Defines compute_b_always(): prints `<index_bytes>\t<core_bytes>\t<sum>`
# (single line, tab-delimited) computed from AGENTS.md (index) and
# AGENTS.core.md (core sidecar). These two files are loaded on every
# SessionStart turn; `AGENTS.docs.md` and `AGENTS.rest.md` are class-loaded
# and do NOT count toward the per-turn always-loaded budget.
#
# Used by:
#   - scripts/lint-agents-rule-budget.sh (pre-commit hook, #3684)
#   - plugins/soleur/skills/compound/SKILL.md step 8 (advisory at compound time)
#   - .github/workflows/scheduled-compound-promote.yml (post-apply revert)
#
# Path overrides for fixture-driven tests:
#   AGENTS_INDEX_PATH (default: AGENTS.md, CWD-relative)
#   AGENTS_CORE_PATH  (default: AGENTS.core.md, CWD-relative)
#
# Missing-file semantics: a missing file contributes 0 bytes (matches the
# pre-existing `wc -c < <file> 2>/dev/null || echo 0` pattern in compound).
# The rule-id residency linter catches genuine renames; silent-zero here is
# not a load-bearing failure mode.
#
# Pure-source library (no shebang, no `+x`). Source from callers via:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/agents-payload-bytes.sh"
#
# See also: scripts/lib/rule-metrics-constants.sh, strip-log-injection.sh
# (sibling pure-source libraries).

compute_b_always() {
  local index_path="${AGENTS_INDEX_PATH:-AGENTS.md}"
  local core_path="${AGENTS_CORE_PATH:-AGENTS.core.md}"
  local index_bytes core_bytes sum
  index_bytes=$(wc -c < "$index_path" 2>/dev/null || echo 0)
  core_bytes=$(wc -c < "$core_path" 2>/dev/null || echo 0)
  # `wc -c <` may emit leading whitespace on some platforms — strip it so
  # the arithmetic and the printed delimiter stay clean.
  index_bytes="${index_bytes//[[:space:]]/}"
  core_bytes="${core_bytes//[[:space:]]/}"
  sum=$((index_bytes + core_bytes))
  printf '%d\t%d\t%d\n' "$index_bytes" "$core_bytes" "$sum"
}
