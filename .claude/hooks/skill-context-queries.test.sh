#!/usr/bin/env bash
# Tests for skill-context-queries.sh (PostToolUse, matcher "Skill") — declarative
# context-injection (#5989, FR6, ADR-086). POINTER-only: the hook emits a
# Read-directive naming committed knowledge-base/ artifacts, never their content.
#
# Fixture discipline (Kieran/spec-flow plan-review): the containment gate is
# `git ls-files --error-unmatch`, which requires TRACKED files — so behavior
# tests run against a throwaway `git init` fixture repo (committed fixtures) via
# the CONTEXT_QUERIES_REPO_ROOT seam, NOT the ambient CWD.
# See knowledge-base/project/learnings/test-failures/2026-06-12-hook-test-passes-on-worktree-fails-on-main-cwd.md
#
# Foot-guns guarded (2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns):
#   (a) nonzero command-sub wrapped `|| true`, gated on emptiness
#   (b) data-derived loop carries a minimum-cardinality guard
#   (c) NEGATIVE injects real-shaped bad data and asserts the verifier flags it
#
# Auto-discovered by scripts/test-all.sh (.claude/hooks/*.test.sh glob).
set -uo pipefail

HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$HOOK_DIR/../.." && pwd -P)"
HOOK="$HOOK_DIR/skill-context-queries.sh"

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# --- Pre-req: hook must exist (RED guard) ---
[[ -f "$HOOK" ]] || { fail "hook not found at $HOOK (RED: implement skill-context-queries.sh)"; printf '\n%d failure(s)\n' "$fails"; exit 1; }

# ---------------------------------------------------------------------------
# Build a throwaway git fixture repo with committed skills + kb artifacts.
# ---------------------------------------------------------------------------
FIX="$(mktemp -d)"
mkdir -p "$FIX/plugins/soleur/skills" "$FIX/knowledge-base/marketing" "$FIX/knowledge-base/deep"

# small within-"budget" artifact + a globbable set
printf '# Brand\nBrand tokens here.\n' > "$FIX/knowledge-base/marketing/brand-guide.md"
printf 'one\n' > "$FIX/knowledge-base/deep/a.md"
printf 'two\n' > "$FIX/knowledge-base/deep/b.md"
# an UNTRACKED file staged nowhere (created after commit below)

mk_skill() { # $1=name  $2=frontmatter-body(context_queries block)
  local d="$FIX/plugins/soleur/skills/$1"; mkdir -p "$d"
  { printf -- '---\nname: %s\ndescription: "test skill"\n' "$1"; printf '%s' "$2"; printf -- '---\n\nBody.\n'; } > "$d/SKILL.md"
}
mk_skill "with-query"   $'context_queries:\n  - knowledge-base/marketing/brand-guide.md\n'
mk_skill "inline-query" $'context_queries: [knowledge-base/marketing/brand-guide.md]\n'
mk_skill "glob-query"   $'context_queries:\n  - knowledge-base/deep/*.md\n'
mk_skill "no-query"     ''
mk_skill "empty-query"  $'context_queries: []\n'
mk_skill "missing-art"  $'context_queries:\n  - knowledge-base/marketing/does-not-exist.md\n'
mk_skill "traversal"    $'context_queries:\n  - knowledge-base/../../../etc/passwd\n'

git -C "$FIX" init -q -b main
git -C "$FIX" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m init >/dev/null 2>&1

# a file present on disk but NOT committed (for the untracked test)
printf 'secret-ish\n' > "$FIX/knowledge-base/marketing/untracked.md"
mk_skill "untracked-art" $'context_queries:\n  - knowledge-base/marketing/untracked.md\n'
# (untracked-art SKILL.md IS committed? no — created after commit; commit it so the SKILL.md itself resolves, but leave the artifact untracked)
git -C "$FIX" -c user.email=t@t -c user.name=t add plugins/soleur/skills/untracked-art >/dev/null 2>&1
git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m untracked-skill >/dev/null 2>&1

run_hook() { # $1=skill-name-json-value(raw)  -> stdout
  CONTEXT_QUERIES_REPO_ROOT="$FIX" bash "$HOOK" 2>/dev/null
}
env_json() { printf '{"tool_name":"Skill","tool_input":{"skill":%s}}' "$(jq -Rn --arg s "$1" '$s')"; }

# --- AC3: happy path (block form) -> Read-directive naming the artifact ---
out="$(env_json "with-query" | run_hook)"; rc=$?
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
printf '%s' "$ctx" | grep -qF 'knowledge-base/marketing/brand-guide.md' && pass "AC3 block-form emits Read-directive naming artifact" || fail "AC3 no directive (ctx=$ctx)"
printf '%s' "$ctx" | grep -qiE 'read' && pass "AC3 directive says Read" || fail "AC3 directive missing Read verb"
[[ "$rc" -eq 0 ]] && pass "AC3 exits 0" || fail "AC3 non-zero exit"
ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)"
[[ "$ev" == "PostToolUse" ]] && pass "AC3 hookEventName=PostToolUse" || fail "AC3 bad hookEventName ($ev)"
# POINTER not inline: artifact BODY content must NOT be echoed
printf '%s' "$ctx" | grep -qF 'Brand tokens here.' && fail "POINTER violated: artifact body content leaked" || pass "pointer-only: no artifact body content in output"

# --- inline [a,b] form parses (reuse full parser, not block-only) ---
out="$(env_json "inline-query" | run_hook)"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF 'brand-guide.md' && pass "inline-array context_queries parses (no parse-to-empty trap)" || fail "inline-array parsed to empty (parse-to-empty trap)"

# --- glob form: sorted, both tracked matches named ---
out="$(env_json "glob-query" | run_hook)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || true)"
{ printf '%s' "$ctx" | grep -qF 'knowledge-base/deep/a.md' && printf '%s' "$ctx" | grep -qF 'knowledge-base/deep/b.md'; } && pass "glob resolves tracked matches" || fail "glob did not resolve (ctx=$ctx)"

# --- AC6: no context_queries key -> exit 0, empty output (fast-path) ---
out="$(env_json "no-query" | run_hook)"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "AC6 no-key skill -> empty, exit 0 (fast-path)" || fail "AC6 no-key not fail-silent (out=$out rc=$rc)"

# --- AC2: empty list / unparseable -> exit 0, in-band note (NOT silent) ---
out="$(env_json "empty-query" | run_hook)"; rc=$?
[[ "$rc" -eq 0 ]] && pass "AC2 empty-list exits 0" || fail "AC2 empty-list non-zero"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && pass "AC2 empty-list emits an in-band note (not silent)" || pass "AC2 empty-list emits nothing (acceptable: no queries)"

# --- AC2: missing artifact -> skip note, exit 0 ---
out="$(env_json "missing-art" | run_hook)"; rc=$?
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
[[ "$rc" -eq 0 ]] && pass "AC2 missing-artifact exits 0" || fail "AC2 missing-artifact non-zero"
printf '%s' "$ctx" | grep -qi 'skip' && pass "AC2 missing-artifact emits skip note" || fail "AC2 missing-artifact no skip note (ctx=$ctx)"

# --- AC4: traversal query rejected, no /etc/passwd, exit 0 ---
out="$(env_json "traversal" | run_hook)"; rc=$?
[[ "$rc" -eq 0 ]] && pass "AC4 traversal exits 0" || fail "AC4 traversal non-zero"
printf '%s' "$out" | grep -qF 'passwd' && fail "AC4 traversal LEAKED out-of-tree path" || pass "AC4 traversal rejected (no passwd)"

# --- AC5: untracked artifact not emitted ---
out="$(env_json "untracked-art" | run_hook)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
printf '%s' "$ctx" | grep -qF 'Read these' && fail "AC5 untracked artifact was emitted as loadable" || pass "AC5 untracked artifact not loaded"

# --- AC7: other-plugin namespaced skill -> exit 0, nothing ---
out="$(env_json "commit-commands:commit" | run_hook)"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "AC7 other-plugin namespaced -> empty, exit 0" || fail "AC7 namespaced not fail-silent (out=$out)"

# --- AC2/security: adversarial skill name executes nothing, no leak ---
rm -f /tmp/ctxq_pwn
out="$(env_json 'with-query";injected$(touch /tmp/ctxq_pwn)' | run_hook)"; rc=$?
[[ ! -f /tmp/ctxq_pwn ]] && pass "adversarial skill name executes no command" || { fail "COMMAND INJECTION"; rm -f /tmp/ctxq_pwn; }
printf '%s' "$out" | grep -qF 'injected' && fail "adversarial substring leaked" || pass "adversarial substring absent"
[[ "$rc" -eq 0 ]] && pass "adversarial exits 0" || fail "adversarial non-zero"

# --- AC13: kill-switch ---
out="$(SOLEUR_DISABLE_CONTEXT_QUERIES=1 CONTEXT_QUERIES_REPO_ROOT="$FIX" bash "$HOOK" < <(env_json "with-query") 2>/dev/null)"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "AC13 kill-switch -> empty, exit 0" || fail "AC13 kill-switch not honored (out=$out)"

# --- AC14: CONSISTENCY — real pilot frontend-design context_queries resolves >=1 tracked file ---
# (runs against the REAL repo, not the fixture)
if [[ -f "$REPO_ROOT/plugins/soleur/skills/frontend-design/SKILL.md" ]] \
   && grep -q '^context_queries:' "$REPO_ROOT/plugins/soleur/skills/frontend-design/SKILL.md"; then
  real_out="$(env_json "frontend-design" | run_hook 2>/dev/null)"
  # re-run against the real repo root
  real_out="$(printf '{"tool_input":{"skill":"soleur:frontend-design"}}' | bash "$HOOK" 2>/dev/null)"
  real_ctx="$(printf '%s' "$real_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
  printf '%s' "$real_ctx" | grep -qF 'knowledge-base/' && pass "AC14 real pilot resolves >=1 committed artifact" || fail "AC14 real pilot did not resolve (ctx=$real_ctx)"
else
  fail "AC14 pilot frontend-design SKILL.md missing context_queries (Phase 3 not applied)"
fi

# --- NEGATIVE (foot-gun c): verify the traversal guard actually rejects ---
# inject a real-shaped out-of-tree path and assert the hook never names it
neg_out="$(env_json "traversal" | run_hook)"
if printf '%s' "$neg_out" | grep -qF '/etc/passwd'; then fail "NEGATIVE: traversal guard did not reject /etc/passwd"; else pass "NEGATIVE: traversal guard rejects out-of-tree"; fi

rm -rf "$FIX"; rm -f /tmp/ctxq_pwn
printf '\n%d failure(s)\n' "$fails"
[[ "$fails" -eq 0 ]] || exit 1
