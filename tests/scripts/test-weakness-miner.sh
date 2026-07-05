#!/usr/bin/env bash
# Tests for scripts/weakness-miner.sh (#6037) — read-only weakness-miner.
# Isolated temp roots so the real learnings corpus / digest are never touched.
# NOTE: no `set -e` — this is an accumulate-then-exit gate; a nonzero probe
# inside a command substitution must not abort before _report prints.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/weakness-miner.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

# Write a learning file with a given tags array. $1=path $2=comma-sep tags
_learning() {
  local path="$1" tags="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
date: 2026-07-05
category: workflow-patterns
tags: [${tags}]
---
# Learning: fixture
## Session Errors
none.
EOF
}

# ---------------------------------------------------------------------------
# Test 1 — clustering: a tag-pair in >=3 files ranks; a pair in 2 files does not.
# Uses SOLEUR_WM_FILES to feed an explicit file list (bypasses git selection).
# ---------------------------------------------------------------------------
t_clustering() {
  local root; root=$(mktemp -d)
  # 3 files share (ci, drift-guard); only 2 share (supabase, rls)
  _learning "$root/a.md" "ci, drift-guard, bash"
  _learning "$root/b.md" "ci, drift-guard, terraform"
  _learning "$root/c.md" "ci, drift-guard, vitest"
  _learning "$root/d.md" "supabase, rls, migration"
  _learning "$root/e.md" "supabase, rls, storage"
  local digest="$root/digest.md"
  SOLEUR_WM_FILES="$(printf '%s\n' "$root/a.md" "$root/b.md" "$root/c.md" "$root/d.md" "$root/e.md")" \
    SOLEUR_WM_DIGEST_PATH="$digest" SOLEUR_WM_MIN_MEMBERS=3 \
    bash "$SCRIPT" >/dev/null 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then _report "clustering: script runs" FAIL "(exit $rc)"; return; fi
  _report "clustering: script runs" ok
  if grep -qiE 'drift-guard.*—.*3 learnings|3 learnings' "$digest" && grep -qi 'drift-guard' "$digest"; then
    _report "clustering: >=3 pair (ci+drift-guard) ranked" ok
  else
    _report "clustering: >=3 pair (ci+drift-guard) ranked" FAIL "(digest: $(tr '\n' '|' <"$digest"))"
  fi
  # the 2-member (supabase+rls) pair must NOT be a ranked cluster heading
  if grep -qE '^###.*supabase.*rls|^###.*rls.*supabase' "$digest"; then
    _report "clustering: 2-member pair suppressed" FAIL "(supabase+rls should not rank)"
  else
    _report "clustering: 2-member pair suppressed" ok
  fi
}

# ---------------------------------------------------------------------------
# Test 2 — git first-appearance window: only in-window learnings are selected.
# Real temp git repo; controlled commit dates; NO SOLEUR_WM_FILES so the script
# uses --diff-filter=A first-appearance selection. SOLEUR_WM_SINCE pins cutoff.
# ---------------------------------------------------------------------------
t_git_window() {
  local root; root=$(mktemp -d)
  ( cd "$root" && git init -q -b main && git config user.email t@t && git config user.name t )
  local ld="$root/knowledge-base/project/learnings"
  # OLD file first-appears 2026-01-01 (out of window)
  _learning "$ld/old.md" "oldtag-x, oldtag-y, oldtag-z"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-01-01T00:00:00" GIT_COMMITTER_DATE="2026-01-01T00:00:00" git commit -q -m old )
  # NEW files first-appear 2026-07-05 (in window); 3 share (win-a, win-b)
  _learning "$ld/n1.md" "win-a, win-b, x1"
  _learning "$ld/n2.md" "win-a, win-b, x2"
  _learning "$ld/n3.md" "win-a, win-b, x3"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-07-05T00:00:00" GIT_COMMITTER_DATE="2026-07-05T00:00:00" git commit -q -m new )
  local digest="$root/digest.md"
  ( cd "$root" && SOLEUR_WM_LEARNINGS_DIR="knowledge-base/project/learnings" \
      SOLEUR_WM_DIGEST_PATH="digest.md" SOLEUR_WM_SINCE="2026-06-28" SOLEUR_WM_MIN_MEMBERS=3 \
      bash "$SCRIPT" >/dev/null 2>&1 )
  if grep -qi 'win-a' "$digest" && ! grep -qi 'oldtag' "$digest"; then
    _report "git-window: in-window selected, out-of-window excluded" ok
  else
    _report "git-window: in-window selected, out-of-window excluded" FAIL "(digest: $(tr '\n' '|' <"$digest" 2>/dev/null))"
  fi
}

# ---------------------------------------------------------------------------
# Test 3 — zero-mutation: after a run in a git repo, ONLY the digest path is
# modified (AC4a). The digest is the single write sink.
# ---------------------------------------------------------------------------
t_zero_mutation() {
  local root; root=$(mktemp -d)
  ( cd "$root" && git init -q -b main && git config user.email t@t && git config user.name t )
  local ld="$root/knowledge-base/project/learnings"
  _learning "$ld/z1.md" "za, zb, z1"
  _learning "$ld/z2.md" "za, zb, z2"
  _learning "$ld/z3.md" "za, zb, z3"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-07-05T00:00:00" GIT_COMMITTER_DATE="2026-07-05T00:00:00" git commit -q -m seed )
  ( cd "$root" && SOLEUR_WM_LEARNINGS_DIR="knowledge-base/project/learnings" \
      SOLEUR_WM_DIGEST_PATH="knowledge-base/project/weakness-digest.md" \
      SOLEUR_WM_SINCE="2026-06-28" SOLEUR_WM_MIN_MEMBERS=3 bash "$SCRIPT" >/dev/null 2>&1 )
  local dirty; dirty="$(cd "$root" && git status --porcelain | awk '{print $2}' | sort -u)"
  if [[ "$dirty" == "knowledge-base/project/weakness-digest.md" ]]; then
    _report "zero-mutation: only digest path modified" ok
  else
    _report "zero-mutation: only digest path modified" FAIL "(dirty: ${dirty//$'\n'/,})"
  fi
}

# ---------------------------------------------------------------------------
# Test 4 — no-cluster case: fewer than MIN_MEMBERS sharing a pair → benign note.
# ---------------------------------------------------------------------------
t_no_cluster() {
  local root; root=$(mktemp -d)
  _learning "$root/a.md" "solo-a, solo-b"
  _learning "$root/b.md" "solo-c, solo-d"
  local digest="$root/digest.md"
  SOLEUR_WM_FILES="$(printf '%s\n' "$root/a.md" "$root/b.md")" \
    SOLEUR_WM_DIGEST_PATH="$digest" SOLEUR_WM_MIN_MEMBERS=3 \
    bash "$SCRIPT" >/dev/null 2>&1
  if grep -qiE 'no recurring pattern' "$digest"; then
    _report "no-cluster: benign note rendered" ok
  else
    _report "no-cluster: benign note rendered" FAIL "(digest: $(tr '\n' '|' <"$digest" 2>/dev/null))"
  fi
}

# ---------------------------------------------------------------------------
# Test 5 — workflow mutation boundary (AC4b): the bot-PR `add-paths` is exactly
# the single digest path and never widens.
# ---------------------------------------------------------------------------
t_workflow_addpaths() {
  local wf="$REPO_ROOT/.github/workflows/weakness-miner.yml"
  if [[ ! -f "$wf" ]]; then _report "workflow: exists" FAIL "(missing $wf)"; return; fi
  local ap; ap="$(awk '/add-paths:/{gsub(/^[[:space:]]*add-paths:[[:space:]]*/,"");print;exit}' "$wf")"
  if [[ "$ap" == "knowledge-base/project/weakness-digest.md" ]]; then
    _report "workflow: add-paths is single digest path (AC4b)" ok
  else
    _report "workflow: add-paths is single digest path (AC4b)" FAIL "(got: '$ap')"
  fi
}

t_clustering
t_git_window
t_zero_mutation
t_no_cluster
t_workflow_addpaths

echo "----"
echo "weakness-miner: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
