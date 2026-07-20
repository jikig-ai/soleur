#!/usr/bin/env bash
set -euo pipefail

# Tests for .claude/hooks/session-rules-loader.sh (issue #3493).
#
# Same convention as security_reminder_hook.test.sh:
#   - Subshell isolation, PASS/FAIL/TOTAL counters
#   - Inline JSON fixtures via printf
#   - Skips silently on missing prerequisites (python3, jq, git)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-rules-loader.sh"

PASS=0
FAIL=0
TOTAL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"; exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH"; exit 0
fi
if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: $HOOK not executable or missing — Phase 4 GREEN required"
  exit 1
fi

# Make a temp repo with sidecar fixtures + an `origin/main` baseline so
# `git diff --name-only origin/main...HEAD` is meaningful.
setup_repo() {
  local repo="$1" change_pattern="${2:-}" mcp_variant="${3:-}"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q -b main
    git config user.email t@test
    git config user.name t
    # Sidecars with one rule body each (so the loader has content to concat).
    cat > AGENTS.core.md <<'CORE'
# AGENTS Core
## Hard Rules
- Core rule [id: hr-test-core].
CORE
    cat > AGENTS.docs.md <<'DOCS'
# AGENTS Docs
## Code Quality
- Docs rule [id: cq-test-docs].
DOCS
    cat > AGENTS.rest.md <<'REST'
# AGENTS Rest
## Code Quality
- Rest rule [id: cq-test-rest].
REST
    cat > AGENTS.md <<'IDX'
# Index
## Hard Rules
- [id: hr-test-core] → core
## Code Quality
- [id: cq-test-docs] → docs
- [id: cq-test-rest] → rest
IDX
    # MCP capability-roster fixtures (#5319). The hook reads .mcp.json and
    # plugins/soleur/.claude-plugin/plugin.json from REPO_ROOT. Seed per variant;
    # committed in the baseline so they do NOT appear in the change-class diff.
    #   ""        → seed nothing (default; preserves pre-#5319 fixture shape, also AC3)
    #   both      → .mcp.json={playwright} ∪ plugin.json={context7,stripe}
    #   malformed → .mcp.json=invalid-JSON + plugin.json={context7,stripe} (AC10)
    case "$mcp_variant" in
      both|malformed)
        mkdir -p plugins/soleur/.claude-plugin
        printf '%s\n' '{"mcpServers":{"context7":{},"stripe":{}}}' > plugins/soleur/.claude-plugin/plugin.json
        ;;
    esac
    case "$mcp_variant" in
      both)      printf '%s\n' '{"mcpServers":{"playwright":{}}}' > .mcp.json ;;
      malformed) printf '%s\n' '{invalid json' > .mcp.json ;;
    esac
    git add . && git commit -q -m baseline
    # Simulate origin/main pointing at the baseline so `origin/main...HEAD`
    # is empty by default. Individual tests overlay extra commits.
    git branch -f origin/main HEAD
    git update-ref refs/remotes/origin/main HEAD
    if [[ -n "$change_pattern" ]]; then
      case "$change_pattern" in
        docs)  echo "doc edit" >> README.md ; git add README.md ; git commit -q -m doc ;;
        code)  printf 'export const x = 1;\n' > app.ts ; git add app.ts ; git commit -q -m code ;;
        infra) mkdir -p apps/foo/infra && echo "resource x {}" > apps/foo/infra/x.tf ; git add . ; git commit -q -m infra ;;
        mixed) echo "doc" >> README.md ; printf 'export const x = 1;\n' > app.ts ; git add . ; git commit -q -m mixed ;;
      esac
    fi
  )
}

# Invoke the hook with an envelope JSON; capture stdout to parse classes + content.
invoke_hook() {
  local repo="$1" extra_env="${2:-}"
  local payload
  payload=$(jq -nc --arg cwd "$repo" '{cwd: $cwd, session_id: "test-sess-1"}')
  if [[ -n "$extra_env" ]]; then
    printf '%s' "$payload" | env $extra_env "$HOOK"
  else
    printf '%s' "$payload" | "$HOOK"
  fi
}

assert_class() {
  local name="$1" repo="$2" expected_class_set="$3"
  TOTAL=$((TOTAL+1))
  local out actual
  out=$(invoke_hook "$repo") || { echo "FAIL: $name (hook crashed)"; FAIL=$((FAIL+1)); return; }
  actual=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE '\[rules-loader\] loaded: [^ ]+' | head -1 | sed 's/.*loaded: //')
  if [[ "$actual" == "$expected_class_set" ]]; then
    echo "PASS: $name (class=$actual)"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected=$expected_class_set actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

# ------------- Test 1-4: classifier per change-class ------------

T1=$(mktemp -d); setup_repo "$T1" docs
assert_class "classifier docs-only diff → core+docs"  "$T1"  "core+docs-only"

T2=$(mktemp -d); setup_repo "$T2" code
assert_class "classifier code diff → core+rest"        "$T2"  "core+rest"

T3=$(mktemp -d); setup_repo "$T3" infra
assert_class "classifier infra diff → core+rest"       "$T3"  "core+rest"

T4=$(mktemp -d); setup_repo "$T4" mixed
assert_class "classifier mixed diff → core+docs+rest"  "$T4"  "core+docs-only+rest"

T5=$(mktemp -d); setup_repo "$T5" ""
# Empty diff → all sidecars (fail-closed)
assert_class "classifier empty diff → core+docs+rest"  "$T5"  "core+docs-only+rest"

# ------------- Test 6: LOADER_FAIL_CLOSED=1 override ------------

TOTAL=$((TOTAL+1))
T6=$(mktemp -d); setup_repo "$T6" docs
out6=$(invoke_hook "$T6" "LOADER_FAIL_CLOSED=1") || true
actual6=$(printf '%s' "$out6" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE '\[rules-loader\] loaded: [^ ]+' | head -1 | sed 's/.*loaded: //')
if [[ "$actual6" == "core+docs-only+rest" ]]; then
  echo "PASS: LOADER_FAIL_CLOSED=1 forces all sidecars"
  PASS=$((PASS+1))
else
  echo "FAIL: LOADER_FAIL_CLOSED=1 forces all sidecars (got $actual6)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 7: 3-run idempotency (compaction parity) ----

TOTAL=$((TOTAL+1))
T7=$(mktemp -d); setup_repo "$T7" docs
declare -a ids
for i in 1 2 3; do
  m=$(invoke_hook "$T7" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
  if [[ -z "$m" || ! -f "$m" ]]; then
    echo "FAIL: idempotency (manifest not written on run $i)"
    FAIL=$((FAIL+1)); break
  fi
  ids[i]=$(jq -c '.rule_ids_loaded | sort' "$m")
done
if [[ -n "${ids[1]:-}" && "${ids[1]}" == "${ids[2]}" && "${ids[2]}" == "${ids[3]}" ]]; then
  echo "PASS: idempotency (3 runs identical rule_ids_loaded)"
  PASS=$((PASS+1))
elif [[ -n "${ids[1]:-}" ]]; then
  echo "FAIL: idempotency (drift: ${ids[1]} vs ${ids[2]} vs ${ids[3]})"
  FAIL=$((FAIL+1))
fi

# ------------- Test 8: bare-repo path resolution (Kieran P0-1) --

TOTAL=$((TOTAL+1))
T8_PARENT=$(mktemp -d)
git init --bare "$T8_PARENT/repo.git" -q
T8_WT="$T8_PARENT/worktree"
git -C "$T8_PARENT/repo.git" worktree add -q "$T8_WT" -b main 2>/dev/null || true
# Seed the worktree with sidecars
setup_repo "$T8_WT" docs >/dev/null 2>&1 || true
# Force-set origin/main inside worktree
(cd "$T8_WT" && git branch -f origin/main HEAD 2>/dev/null && git update-ref refs/remotes/origin/main HEAD 2>/dev/null) || true
# Invoke from $T8_WT but envelope cwd matches → hook must NOT crash and must classify.
out8_crashed=0
out8=$(printf '%s' "$(jq -nc --arg cwd "$T8_WT" '{cwd: $cwd, session_id: "bare"}')" | "$HOOK" 2>&1) || out8_crashed=1
if (( out8_crashed == 1 )); then
  echo "FAIL: bare-repo path resolution (hook crashed: $(printf '%s' "$out8" | head -c 120))"
  FAIL=$((FAIL+1))
elif [[ -n "$out8" ]] && printf '%s' "$out8" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  echo "PASS: bare-repo path resolution (hook returns JSON with class set)"
  PASS=$((PASS+1))
else
  # Eliminate the silent-skip path: explicit FAIL when stdout is empty or
  # not parseable as the expected JSON envelope.
  echo "FAIL: bare-repo path resolution (no JSON envelope; out8=$(printf '%s' "$out8" | head -c 120))"
  FAIL=$((FAIL+1))
fi

# ------------- Test 9: manifest 3-field schema -----------------

TOTAL=$((TOTAL+1))
T9=$(mktemp -d); setup_repo "$T9" docs
out9=$(invoke_hook "$T9")
manifest9=$(printf '%s' "$out9" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
if [[ -f "$manifest9" ]]; then
  fields=$(jq -r 'keys | sort | @csv' "$manifest9")
  expected='"change_class","rule_ids_loaded","timestamp"'
  if [[ "$fields" == "$expected" ]]; then
    echo "PASS: manifest schema (3 fields exactly)"
    PASS=$((PASS+1))
  else
    echo "FAIL: manifest schema (got $fields, want $expected)"
    FAIL=$((FAIL+1))
  fi
else
  echo "FAIL: manifest schema (no manifest written)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 10: fail-closed on missing sidecar --------

TOTAL=$((TOTAL+1))
T10=$(mktemp -d); setup_repo "$T10" docs
rm -f "$T10/AGENTS.docs.md"
out10=$(invoke_hook "$T10")
ctx10=$(printf '%s' "$out10" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$ctx10" | grep -q 'fail-safe: sidecar missing'; then
  echo "PASS: fail-closed on missing sidecar"
  PASS=$((PASS+1))
else
  echo "FAIL: fail-closed on missing sidecar (no fail-safe marker in stamp)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 11: stamp + hint ≤ 200 bytes per line ----

TOTAL=$((TOTAL+1))
T11=$(mktemp -d); setup_repo "$T11" docs
out11=$(invoke_hook "$T11")
ctx11=$(printf '%s' "$out11" | jq -r '.hookSpecificOutput.additionalContext')
max_line=$(printf '%s' "$ctx11" | head -3 | awk '{ print length }' | sort -n | tail -1)
if (( max_line <= 200 )); then
  echo "PASS: stamp+hint lines ≤ 200 bytes (max=$max_line)"
  PASS=$((PASS+1))
else
  echo "FAIL: stamp+hint line exceeded 200 bytes (max=$max_line)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 12: session_id path traversal sanitized -----------

TOTAL=$((TOTAL+1))
T12=$(mktemp -d); setup_repo "$T12" docs
# Crafted session_id attempting `../../tmp/PWNED.json` escape.
payload12=$(jq -nc --arg cwd "$T12" --arg sid "../../../tmp/PWNED_RULES_LOADER" '{cwd: $cwd, session_id: $sid}')
out12=$(printf '%s' "$payload12" | "$HOOK" 2>/dev/null)
manifest12=$(printf '%s' "$out12" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
if [[ -f "/tmp/PWNED_RULES_LOADER.json" ]]; then
  echo "FAIL: session_id path traversal — /tmp/PWNED_RULES_LOADER.json was created"
  rm -f /tmp/PWNED_RULES_LOADER.json
  FAIL=$((FAIL+1))
elif [[ -n "$manifest12" && "$manifest12" == "$T12/.claude/.session-manifests/"* ]]; then
  echo "PASS: session_id sanitized (manifest stayed inside $T12)"
  PASS=$((PASS+1))
else
  echo "FAIL: session_id path traversal — manifest unexpectedly at $manifest12"
  FAIL=$((FAIL+1))
fi

# ------------- Test 13: cwd outside a git worktree → core-only fallback

TOTAL=$((TOTAL+1))
T13_NONREPO=$(mktemp -d)
cp "$T13_NONREPO/../"*/AGENTS.core.md "$T13_NONREPO/AGENTS.core.md" 2>/dev/null || true
# Use an arbitrary non-repo directory. The hook must refuse to operate
# (no git worktree at cwd → emit core-only fallback, do NOT create
# .claude/.session-manifests/ inside the bogus dir).
payload13=$(jq -nc --arg cwd "$T13_NONREPO" '{cwd: $cwd, session_id: "test-non-repo"}')
out13=$(printf '%s' "$payload13" | "$HOOK" 2>/dev/null)
ctx13=$(printf '%s' "$out13" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx13" | grep -q 'FALLBACK'; then
  echo "PASS: cwd outside git worktree → fallback emitted"
  PASS=$((PASS+1))
else
  echo "FAIL: cwd outside git worktree — expected FALLBACK marker, got: $(printf '%s' "$ctx13" | head -c 120)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 14: symlinked sidecar is rejected (no body read) --

TOTAL=$((TOTAL+1))
T14=$(mktemp -d); setup_repo "$T14" docs
echo "EXFIL_TARGET=symlink-pointed-at-this-file" > /tmp/loader-symlink-target-$$
rm -f "$T14/AGENTS.docs.md"
ln -s "/tmp/loader-symlink-target-$$" "$T14/AGENTS.docs.md"
out14=$(invoke_hook "$T14")
ctx14=$(printf '%s' "$out14" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx14" | grep -q 'EXFIL_TARGET'; then
  echo "FAIL: symlinked sidecar — content from /tmp leaked into context"
  FAIL=$((FAIL+1))
else
  echo "PASS: symlinked sidecar rejected (no exfil content in additionalContext)"
  PASS=$((PASS+1))
fi
rm -f /tmp/loader-symlink-target-$$

# ------------- Test 15 (AC1): workspace fields + dirty count -----------
# The session-context line-1 carries branch + dirty file count. Two untracked
# files in the worktree → `dirty: 2 files`. Note: the snapshot's dirty count is
# computed BEFORE the hook creates .claude/.session-manifests/, so the manifest
# dir never self-inflates the count (mirrors prod where it is gitignored).
TOTAL=$((TOTAL+1))
T15=$(mktemp -d); setup_repo "$T15" docs both
echo "uncommitted A" > "$T15/dirty-a.txt"
echo "uncommitted B" > "$T15/dirty-b.txt"
out15=$(invoke_hook "$T15")
ctx15=$(printf '%s' "$out15" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx15" | grep -qE '^\[session-context\] branch: main \| dirty: 2 files$' \
   && printf '%s' "$ctx15" | grep -qF "[session-context] worktree: $T15"; then
  echo "PASS: AC1 workspace fields (branch + dirty: 2 files + worktree)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC1 workspace fields — got: $(printf '%s' "$ctx15" | grep -F '[session-context]' | head -3 | tr '\n' '~')"
  FAIL=$((FAIL+1))
fi

# ------------- Test 16 (AC2): MCP roster unions both sources -----------
TOTAL=$((TOTAL+1))
T16=$(mktemp -d); setup_repo "$T16" docs both
out16=$(invoke_hook "$T16")
ctx16=$(printf '%s' "$out16" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
mcp16=$(printf '%s' "$ctx16" | grep -F '[session-context] MCP(committed-config):' | head -1 || true)
if printf '%s' "$mcp16" | grep -q 'playwright' \
   && printf '%s' "$mcp16" | grep -q 'context7' \
   && printf '%s' "$mcp16" | grep -q 'stripe'; then
  echo "PASS: AC2 MCP roster unions .mcp.json + plugin.json ($mcp16)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC2 MCP roster union — got: $mcp16"
  FAIL=$((FAIL+1))
fi

# ------------- Test 17 (AC3): fail-open on missing config --------------
TOTAL=$((TOTAL+1))
T17=$(mktemp -d); setup_repo "$T17" docs   # no mcp_variant → neither config file
out17_rc=0
out17=$(invoke_hook "$T17") || out17_rc=$?
ctx17=$(printf '%s' "$out17" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if (( out17_rc == 0 )) \
   && printf '%s' "$ctx17" | grep -qF '[session-context] MCP(committed-config): (none)' \
   && printf '%s' "$ctx17" | grep -qF '[id: hr-test-core]'; then
  echo "PASS: AC3 fail-open missing config (roster=(none), exit 0, rule bodies present)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC3 fail-open missing config (rc=$out17_rc; ctx head=$(printf '%s' "$ctx17" | grep -F '[session-context]' | tr '\n' '~'))"
  FAIL=$((FAIL+1))
fi

# ------------- Test 18 (AC4): fail-open when branch resolution fails ----
# A `git` shim that fails ONLY for `rev-parse --abbrev-ref` and delegates all
# else to real git. The worktree gate (`--is-inside-work-tree`) and the dirty/
# diff queries still succeed, so the hook reaches the snapshot and WS_BRANCH
# degrades to `(unknown)` via the `|| echo "(unknown)"` guard.
TOTAL=$((TOTAL+1))
T18=$(mktemp -d); setup_repo "$T18" docs both
REAL_GIT=$(command -v git)
GITSHIM=$(mktemp -d)
cat > "$GITSHIM/git" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "--abbrev-ref" ]] && exit 1; done
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$GITSHIM/git"
out18_rc=0
out18=$(invoke_hook "$T18" "PATH=$GITSHIM:$PATH") || out18_rc=$?
ctx18=$(printf '%s' "$out18" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if (( out18_rc == 0 )) \
   && printf '%s' "$ctx18" | grep -qE '^\[session-context\] branch: \(unknown\) \| dirty: [0-9]+ files$'; then
  echo "PASS: AC4 fail-open on branch-resolution failure (branch: (unknown), exit 0)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC4 fail-open on branch-resolution failure (rc=$out18_rc; line=$(printf '%s' "$ctx18" | grep -F '[session-context] branch:' | head -1))"
  FAIL=$((FAIL+1))
fi
rm -rf "$GITSHIM"

# ------------- Test 19 (AC7): per-line byte budget + line position -----
# Long branch name (100 chars) + deep worktree path. Each [session-context]
# line must be ≤ 512 bytes, and the 3 session-context lines must sit at envelope
# positions 4-6 (after STAMP/HINT/manifest, outside Test 11's head -3 window).
TOTAL=$((TOTAL+1))
LONGBR=$(printf 'b%.0s' $(seq 1 100))
T19_DEEP=$(mktemp -d)/aaaaaaaaaa/bbbbbbbbbb/cccccccccc/dddddddddd/eeeeeeeeee
mkdir -p "$T19_DEEP"
setup_repo "$T19_DEEP" docs both
( cd "$T19_DEEP" && git checkout -q -b "$LONGBR" )
out19=$(invoke_hook "$T19_DEEP")
ctx19=$(printf '%s' "$out19" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
sc_max=$(printf '%s' "$ctx19" | grep -F '[session-context]' | awk '{ print length }' | sort -n | tail -1 || true)
l4=$(printf '%s' "$ctx19" | sed -n '4p'); l5=$(printf '%s' "$ctx19" | sed -n '5p'); l6=$(printf '%s' "$ctx19" | sed -n '6p')
l3=$(printf '%s' "$ctx19" | sed -n '3p'); l7=$(printf '%s' "$ctx19" | sed -n '7p')
if (( ${sc_max:-0} <= 512 && sc_max > 0 )) \
   && [[ "$l3" == '[rules-loader] manifest: '* ]] \
   && [[ "$l4" == '[session-context]'* && "$l5" == '[session-context]'* && "$l6" == '[session-context]'* ]] \
   && [[ "$l7" != '[session-context]'* ]]; then
  echo "PASS: AC7 byte budget (max=$sc_max ≤ 512) + lines 4-6 are session-context"
  PASS=$((PASS+1))
else
  echo "FAIL: AC7 byte/position (max=$sc_max; l3='${l3:0:40}' l4='${l4:0:40}' l7='${l7:0:40}')"
  FAIL=$((FAIL+1))
fi

# ------------- Test 20 (AC10): fail-open on malformed .mcp.json --------
# Invalid JSON → jq exit-5 (writes nothing to stdout); the roster falls back to
# the plugin.json keys only and the hook still exits 0. This proves the
# malformed-config FAIL-OPEN behavior. Note: the `|| true` guards are
# defense-in-depth, not load-bearing here — `set -e` is off in the hook and the
# jq calls sit in assignment-position command-subs (ERR-exempt), so the fallback
# holds with or without them; the value of this test is the fail-open contract.
TOTAL=$((TOTAL+1))
T20=$(mktemp -d); setup_repo "$T20" docs malformed
out20_rc=0
out20=$(invoke_hook "$T20") || out20_rc=$?
ctx20=$(printf '%s' "$out20" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
mcp20=$(printf '%s' "$ctx20" | grep -F '[session-context] MCP(committed-config):' | head -1 || true)
if (( out20_rc == 0 )) \
   && printf '%s' "$mcp20" | grep -q 'context7' \
   && printf '%s' "$mcp20" | grep -q 'stripe' \
   && ! printf '%s' "$mcp20" | grep -q 'playwright' \
   && printf '%s' "$ctx20" | grep -qF '[id: hr-test-core]'; then
  echo "PASS: AC10 malformed .mcp.json → plugin.json keys only, exit 0 ($mcp20)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC10 malformed .mcp.json (rc=$out20_rc; mcp=$mcp20)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 21 (AC11): control-char / newline sanitization ------
# A JSON key may legally contain a newline or other control char. Without the
# per-key gsub("[[:cntrl:]]") strip in the hook, an embedded newline splits one
# server into two roster entries and a raw control char lands verbatim in the
# agent's context. Assert the roster collapses to a single CLEAN token and the
# session-context block stays exactly 3 lines (no envelope line-shift).
TOTAL=$((TOTAL+1))
T21=$(mktemp -d); setup_repo "$T21" docs
# JSON-escaped key contains an embedded newline (valid JSON \n escape, not a
# literal newline byte). Without the hook's per-key gsub("[[:cntrl:]]") strip the
# newline would split this into two roster entries; after gsub it collapses to a
# single clean token "abinjected".
jq -nc '{mcpServers:{"ab\ninjected":{}}}' > "$T21/.mcp.json"
out21=$(invoke_hook "$T21")
ctx21=$(printf '%s' "$out21" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
mcp21=$(printf '%s' "$ctx21" | grep -F '[session-context] MCP(committed-config):' | head -1 || true)
sc_count21=$(printf '%s' "$ctx21" | grep -cF '[session-context]' || true)
l7_21=$(printf '%s' "$ctx21" | sed -n '7p')
if printf '%s' "$mcp21" | grep -qE 'MCP\(committed-config\): abinjected$' \
   && [[ "$sc_count21" == "3" ]] \
   && [[ "$l7_21" != '[session-context]'* ]]; then
  echo "PASS: AC11 control-char sanitization (single clean token, 3 session-context lines)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC11 control-char sanitization (mcp='$mcp21' sc_count=$sc_count21 l7='${l7_21:0:40}')"
  FAIL=$((FAIL+1))
fi

# ------------- Test 22 (AC6): frontmatter stripped on the MAIN-CONCAT path --
# A frontmatter-bearing AGENTS.core.md → injected context carries the rule
# bodies but NOT the YAML frontmatter keys (last_reviewed / review_cadence).
# The fixture includes the sentinel rule-id so the over-strip guard's
# was-present-then-gone clause has something to verify survived.
write_frontmatter_core() {
  cat > "$1/AGENTS.core.md" <<'CORE'
---
last_reviewed: 2026-07-05
review_cadence: monthly
owner: founder
---

# AGENTS Core

## Hard Rules

- Core rule [id: hr-test-core].
- Never git stash in worktrees [id: hr-never-git-stash-in-worktrees].
CORE
}
TOTAL=$((TOTAL+1))
T22=$(mktemp -d); setup_repo "$T22" ""
write_frontmatter_core "$T22"
out22=$(invoke_hook "$T22")
ctx22=$(printf '%s' "$out22" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx22" | grep -qF '[id: hr-test-core]' \
   && printf '%s' "$ctx22" | grep -qF '[id: hr-never-git-stash-in-worktrees]' \
   && ! printf '%s' "$ctx22" | grep -q 'last_reviewed:' \
   && ! printf '%s' "$ctx22" | grep -q 'review_cadence:' \
   && ! printf '%s' "$ctx22" | grep -qE '^\[rules-loader\] loaded:.*over-strip'; then
  echo "PASS: AC6 main-concat strips frontmatter, keeps rules"
  PASS=$((PASS+1))
else
  echo "FAIL: AC6 main-concat strip (ctx head=$(printf '%s' "$ctx22" | head -8 | tr '\n' '~'))"
  FAIL=$((FAIL+1))
fi

# ------------- Test 23 (AC6): frontmatter stripped on the CORE-ONLY FALLBACK path (:50)
# cwd NOT inside a git worktree → emit_core_only_fallback fires, reading
# AGENTS.core.md via emit_stripped_sidecar. Frontmatter must be stripped there
# too (the error path is not exempt).
TOTAL=$((TOTAL+1))
T23=$(mktemp -d)   # NOT a git repo
write_frontmatter_core "$T23"
payload23=$(jq -nc --arg cwd "$T23" '{cwd: $cwd, session_id: "fallback-strip"}')
out23=$(printf '%s' "$payload23" | "$HOOK" 2>/dev/null)
ctx23=$(printf '%s' "$out23" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx23" | grep -q 'FALLBACK' \
   && printf '%s' "$ctx23" | grep -qF '[id: hr-test-core]' \
   && ! printf '%s' "$ctx23" | grep -q 'last_reviewed:' \
   && ! printf '%s' "$ctx23" | grep -q 'review_cadence:'; then
  echo "PASS: AC6 core-only fallback (:50) strips frontmatter, keeps rules"
  PASS=$((PASS+1))
else
  echo "FAIL: AC6 core-only fallback strip (ctx head=$(printf '%s' "$ctx23" | head -6 | tr '\n' '~'))"
  FAIL=$((FAIL+1))
fi

# ------------- Test 24 (AC6): over-strip guard on MALFORMED frontmatter -----
# An unterminated leading `---` would make the strip consume the whole sidecar
# (empty output). The over-strip guard MUST detect this (rule count / sentinel
# drop), inject the RAW sidecar instead (no `- [id:` rule line lost), and mark
# the stamp with a loud over-strip note.
TOTAL=$((TOTAL+1))
T24=$(mktemp -d); setup_repo "$T24" ""
cat > "$T24/AGENTS.core.md" <<'CORE'
---
last_reviewed: 2026-07-05
review_cadence: monthly

# AGENTS Core (unterminated frontmatter — no closing ---)

## Hard Rules

- Core rule [id: hr-test-core].
- Never git stash in worktrees [id: hr-never-git-stash-in-worktrees].
CORE
out24=$(invoke_hook "$T24")
ctx24=$(printf '%s' "$out24" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx24" | grep -qF '[id: hr-test-core]' \
   && printf '%s' "$ctx24" | grep -qF '[id: hr-never-git-stash-in-worktrees]' \
   && printf '%s' "$ctx24" | grep -qE '^\[rules-loader\] loaded:.*over-strip'; then
  echo "PASS: AC6 malformed frontmatter → over-strip guard injects raw (no rule lost) + loud note"
  PASS=$((PASS+1))
else
  echo "FAIL: AC6 over-strip guard (ctx head=$(printf '%s' "$ctx24" | head -3 | tr '\n' '~'))"
  FAIL=$((FAIL+1))
fi

echo ""
echo "RESULT: $PASS/$TOTAL passed ($FAIL failed)"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
