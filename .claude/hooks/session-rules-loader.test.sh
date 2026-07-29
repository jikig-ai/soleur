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

# Make a temp repo with a rule-corpus fixture + an `origin/main` baseline.
# ADR-151 retired the change-class classifier, so the change_pattern argument no
# longer selects which bodies load (the whole corpus always loads); it is kept
# because several tests still exercise diff-shaped repos and the session-context
# snapshot reads git state.
setup_repo() {
  local repo="$1" change_pattern="${2:-}" mcp_variant="${3:-}"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q -b main
    git config user.email t@test
    git config user.name t
    # One corpus holding every rule body (ADR-151).
    cat > AGENTS.rules.md <<'RULES'
# AGENTS Rules
## Hard Rules
- Core rule [id: hr-test-core].
## Code Quality
- Docs rule [id: cq-test-docs].
- Rest rule [id: cq-test-rest].
RULES
    cat > AGENTS.md <<'IDX'
# Index
## Hard Rules
- [id: hr-test-core]
## Code Quality
- [id: cq-test-docs]
- [id: cq-test-rest]
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

# Tests 1-6 (per-change-class classifier assertions and the fail-closed override)
# were DELETED by ADR-151: there is no classifier to assert and no override to
# force, because the whole corpus loads on every session. The property they
# protected — "the rules that should be in context are in context" — is now
# structural; what remains observable is the stamp's numerator/denominator,
# covered by Tests 25 and 27 below.

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
rm -f "$T10/AGENTS.rules.md"
out10=$(invoke_hook "$T10")
ctx10=$(printf '%s' "$out10" | jq -r '.hookSpecificOutput.additionalContext')
# Both halves matter: the operator must see WHY, and the numerator must show 0
# (a missing corpus that stamped "3 of 3" would be the governance blackout).
if printf '%s' "$ctx10" | grep -q 'fail-safe: corpus missing' \
   && printf '%s' "$ctx10" | grep -qE 'loaded: 0 of [0-9]+ rules'; then
  echo "PASS: fail-closed on missing corpus (0-of-N + cause)"
  PASS=$((PASS+1))
else
  echo "FAIL: fail-closed on missing corpus — got: $(printf '%s' "$ctx10" | head -1)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 11: header lines ≤ 200 bytes each ----

TOTAL=$((TOTAL+1))
T11=$(mktemp -d); setup_repo "$T11" docs
out11=$(invoke_hook "$T11")
ctx11=$(printf '%s' "$out11" | jq -r '.hookSpecificOutput.additionalContext')
# head -2: the operator-glanceable header is STAMP(1) + manifest(2). It was
# head -3 until ADR-151 removed the HINT line.
max_line=$(printf '%s' "$ctx11" | head -2 | awk '{ print length }' | sort -n | tail -1)
if (( max_line <= 200 )); then
  echo "PASS: header lines ≤ 200 bytes (max=$max_line)"
  PASS=$((PASS+1))
else
  echo "FAIL: header line exceeded 200 bytes (max=$max_line)"
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
cp "$T13_NONREPO/../"*/AGENTS.rules.md "$T13_NONREPO/AGENTS.rules.md" 2>/dev/null || true
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

# ------------- Test 14: symlinked corpus is rejected (no body read) --

TOTAL=$((TOTAL+1))
T14=$(mktemp -d); setup_repo "$T14" docs
echo "EXFIL_TARGET=symlink-pointed-at-this-file" > /tmp/loader-symlink-target-$$
rm -f "$T14/AGENTS.rules.md"
ln -s "/tmp/loader-symlink-target-$$" "$T14/AGENTS.rules.md"
out14=$(invoke_hook "$T14")
ctx14=$(printf '%s' "$out14" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if printf '%s' "$ctx14" | grep -q 'EXFIL_TARGET'; then
  echo "FAIL: symlinked corpus — content from /tmp leaked into context"
  FAIL=$((FAIL+1))
else
  echo "PASS: symlinked corpus rejected (no exfil content in additionalContext)"
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
# positions 3-5 (after STAMP/manifest, outside Test 11's head -2 window).
# Was 4-6 until ADR-151 removed the HINT line from the header.
TOTAL=$((TOTAL+1))
LONGBR=$(printf 'b%.0s' $(seq 1 100))
T19_DEEP=$(mktemp -d)/aaaaaaaaaa/bbbbbbbbbb/cccccccccc/dddddddddd/eeeeeeeeee
mkdir -p "$T19_DEEP"
setup_repo "$T19_DEEP" docs both
( cd "$T19_DEEP" && git checkout -q -b "$LONGBR" )
out19=$(invoke_hook "$T19_DEEP")
ctx19=$(printf '%s' "$out19" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
sc_max=$(printf '%s' "$ctx19" | grep -F '[session-context]' | awk '{ print length }' | sort -n | tail -1 || true)
l3=$(printf '%s' "$ctx19" | sed -n '3p'); l4=$(printf '%s' "$ctx19" | sed -n '4p'); l5=$(printf '%s' "$ctx19" | sed -n '5p')
l2=$(printf '%s' "$ctx19" | sed -n '2p'); l6=$(printf '%s' "$ctx19" | sed -n '6p')
if (( ${sc_max:-0} <= 512 && sc_max > 0 )) \
   && [[ "$l2" == '[rules-loader] manifest: '* ]] \
   && [[ "$l3" == '[session-context]'* && "$l4" == '[session-context]'* && "$l5" == '[session-context]'* ]] \
   && [[ "$l6" != '[session-context]'* ]]; then
  echo "PASS: AC7 byte budget (max=$sc_max ≤ 512) + lines 3-5 are session-context"
  PASS=$((PASS+1))
else
  echo "FAIL: AC7 byte/position (max=$sc_max; l2='${l2:0:40}' l3='${l3:0:40}' l6='${l6:0:40}')"
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
l6_21=$(printf '%s' "$ctx21" | sed -n '6p')
if printf '%s' "$mcp21" | grep -qE 'MCP\(committed-config\): abinjected$' \
   && [[ "$sc_count21" == "3" ]] \
   && [[ "$l6_21" != '[session-context]'* ]]; then
  echo "PASS: AC11 control-char sanitization (single clean token, 3 session-context lines)"
  PASS=$((PASS+1))
else
  echo "FAIL: AC11 control-char sanitization (mcp='$mcp21' sc_count=$sc_count21 l6='${l6_21:0:40}')"
  FAIL=$((FAIL+1))
fi

# ------------- Test 22 (AC6): frontmatter stripped on the MAIN-CONCAT path --
# A frontmatter-bearing corpus → injected context carries the rule
# bodies but NOT the YAML frontmatter keys (last_reviewed / review_cadence).
# The fixture includes the sentinel rule-id so the over-strip guard's
# was-present-then-gone clause has something to verify survived.
write_frontmatter_core() {
  cat > "$1/AGENTS.rules.md" <<'CORE'
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
# the corpus via emit_stripped_sidecar. Frontmatter must be stripped there
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
cat > "$T24/AGENTS.rules.md" <<'CORE'
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

# ---------------------------------------------------------------------------
# tmpfs-guard alarm surfacing (#6991).
#
# The guard writes these files from cron; this hook is the only channel by
# which they reach a human. Every arm pins the files to a fixture — the
# defaults point at the operator's real $HOME, so an unpinned arm would read
# live machine state and pass or fail for reasons unrelated to the code.
# ---------------------------------------------------------------------------
TALARM=$(mktemp -d)
# Owning trap (ADR-129). The pre-existing T1..T9 fixture dirs above predate the
# lint and are grandfathered by its diff scoping; this one is new, so it cleans
# up after itself rather than adding to the /tmp entry count the sibling half of
# this very PR exists to report on.
trap 'rm -rf "$TALARM"' EXIT
setup_repo "$TALARM" docs
ALARM_FIX="$TALARM/alarm-fixture.log"
HB_FIX="$TALARM/heartbeat-fixture"

# AC-T1: a healthy machine injects nothing. A banner on every session for a
# machine with no problem is how the previous channel earned its silence.
TOTAL=$((TOTAL+1))
rm -f "$ALARM_FIX" "$HB_FIX"
ctx_alarm_none=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
if ! printf '%s' "$ctx_alarm_none" | grep -qF '[tmpfs-guard]'; then
  echo "PASS: AC-T1 no alarm file → nothing injected"
  PASS=$((PASS+1))
else
  echo "FAIL: AC-T1 injected a tmpfs-guard block with no alarm present"
  FAIL=$((FAIL+1))
fi

# AC-T2: an alarm is rendered, and lines 3-5 stay the session-context triple.
# That positional contract is asserted by AC7/AC11 above; splicing the alarm
# into the line-4 slot would red them the first time the guard fires, i.e.
# during the incident, presenting as an unrelated loader regression.
TOTAL=$((TOTAL+1))
printf '2026-07-27T10:00:00Z /tmp at 91%% — nothing reapable found.\n' > "$ALARM_FIX"
ctx_alarm=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
al3=$(printf '%s' "$ctx_alarm" | sed -n '3p')
al4=$(printf '%s' "$ctx_alarm" | sed -n '4p')
al5=$(printf '%s' "$ctx_alarm" | sed -n '5p')
if printf '%s' "$ctx_alarm" | grep -qF '/tmp at 91%' \
   && [[ "$al3" == '[session-context]'* ]] \
   && [[ "$al4" == '[session-context]'* ]] \
   && [[ "$al5" == '[session-context]'* ]]; then
  echo "PASS: AC-T2 alarm rendered without displacing the lines 3-5 contract"
  PASS=$((PASS+1))
else
  echo "FAIL: AC-T2 alarm rendering (l3='$al3')"
  FAIL=$((FAIL+1))
fi

# AC-T3: the alarm file is cron-written input reaching the top of every agent
# session. Control characters are stripped and the line is capped, matching how
# this file already treats the MCP roster and the worktree path.
TOTAL=$((TOTAL+1))
{ printf '2026-07-27T10:00:00Z NASTY\001\002CTRL '; head -c 3000 /dev/zero | tr '\0' 'Z'; printf '\n'; } > "$ALARM_FIX"
ctx_nasty=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
nasty_line=$(printf '%s' "$ctx_nasty" | grep -F '[tmpfs-guard]' | head -1)
nasty_ctrl=$(printf '%s' "$nasty_line" | tr -cd '\001-\010\013\014\016-\037' | wc -c)
if [[ "$nasty_ctrl" -eq 0 ]] && [[ "${#nasty_line}" -le 512 ]]; then
  echo "PASS: AC-T3 alarm content is control-char stripped and length-capped"
  PASS=$((PASS+1))
else
  echo "FAIL: AC-T3 sanitization (ctrl=$nasty_ctrl len=${#nasty_line})"
  FAIL=$((FAIL+1))
fi

# AC-T4: a stale heartbeat reports that the guard stopped running. This is the
# only signal that can: a dead guard writes no alarms, so an absent alarm file
# reads as health. An ABSENT heartbeat is not an alarm — it means the guard has
# never run here (a fresh checkout), which must stay silent.
TOTAL=$((TOTAL+1))
rm -f "$ALARM_FIX"
printf '2026-07-27T09:00:00Z run complete\n' > "$HB_FIX"
touch -d '-90 minutes' "$HB_FIX"
ctx_stale=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
touch "$HB_FIX"
ctx_fresh=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
rm -f "$HB_FIX"
ctx_absent=$(invoke_hook "$TALARM" "TMPFS_GUARD_ALARM_FILE=$ALARM_FIX TMPFS_GUARD_HEARTBEAT_FILE=$HB_FIX" \
  | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$ctx_stale" | grep -qF 'no completed run' \
   && ! printf '%s' "$ctx_fresh" | grep -qF 'no completed run' \
   && ! printf '%s' "$ctx_absent" | grep -qF 'no completed run'; then
  echo "PASS: AC-T4 stale heartbeat reported; fresh and absent stay silent"
  PASS=$((PASS+1))
else
  echo "FAIL: AC-T4 heartbeat staleness detection"
  FAIL=$((FAIL+1))
fi

# Owning trap (ADR-129) for the late-added fixtures below (#7008). The block above already
# registers an EXIT trap for $TALARM, and a bare re-register REPLACES it — so
# this one covers BOTH. Parent-scope append is the shape the ownership lint
# recognizes (scripts/lint-trap-tempfile-ownership).
LATE_TMPDIRS=()
trap 'rm -rf "${TALARM:-}" ${LATE_TMPDIRS[@]+"${LATE_TMPDIRS[@]}"}' EXIT

# ------------- Test 25: stamp denominator counts rule BODIES, not bodies+index ----
# The fixture repo carries 3 index pointers in AGENTS.md AND 3 rule bodies across
# the sidecars. A denominator globbed over AGENTS*.md spans BOTH and reports 6 —
# i.e. "3 of 6" (looks like 50%) when 100% of a 3-rule corpus is loaded. #7008.

TOTAL=$((TOTAL+1))
T25=$(mktemp -d); LATE_TMPDIRS+=("$T25"); setup_repo "$T25" mixed
out25=$(invoke_hook "$T25")
ctx25=$(printf '%s' "$out25" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
stamp25=$(printf '%s' "$ctx25" | head -1)
# Tolerate trailing stamp fields (byte figure, notes); `|| true` so a
# non-match reports a clear FAIL instead of aborting the suite under `set -e`.
den25=$(printf '%s' "$stamp25" | sed -nE 's/.*loaded: [0-9]+ of ([0-9]+) rules.*/\1/p' || true)
# Independently re-derive the body count from the corpus only.
bodies25=$(grep -hE '^- .*\[id: ' "$T25"/AGENTS.rules.md | wc -l | tr -d ' ')
if [[ "$den25" == "$bodies25" ]]; then
  echo "PASS: stamp denominator == corpus body count ($den25)"
  PASS=$((PASS+1))
else
  echo "FAIL: stamp denominator=$den25 but corpus bodies=$bodies25 (stamp: $stamp25)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 26: denominator must come from a FIXED expected set ----
# Two regressions this pins, both of which render a truncated corpus as 100%:
#   (a) an `AGENTS*` glob (with or without `.md`) also matches the index;
#   (b) deriving the count from $CONTEXT / the sidecars actually loaded, which
#       degrades in lockstep with the numerator.
# Anchored on shape, not on a bare literal, and comment lines are stripped so
# the loader may still NAME the retired forms when explaining them.

TOTAL=$((TOTAL+1))
code26=$(grep -vE '^[[:space:]]*#' "$HOOK")
bad26=""
printf '%s' "$code26" | grep -qE 'AGENTS[^"[:space:]]*\*' && bad26="glob spanning the index"
printf '%s' "$code26" | grep -qE 'TOTAL_RULES=.*\$(CONTEXT|CORPUS)' && bad26="denominator derived from loaded sidecars"
if [[ -z "$bad26" ]]; then
  echo "PASS: denominator derives from a fixed expected set"
  PASS=$((PASS+1))
else
  echo "FAIL: $bad26 — a truncated corpus would stamp as 100%"
  FAIL=$((FAIL+1))
fi

# ------------- Test 27: a TRUNCATED corpus -> numerator < denominator ----
# Under one unconditional corpus the happy path always stamps N of N, so the
# numerator and denominator are indistinguishable there and a lockstep-collapse
# bug would be invisible. A proper SUBSET is the only shape that pins the
# numerator. Before ADR-151 this arm used a docs-only class fixture; the
# equivalent shape now is a corpus TRUNCATED after the index was written —
# exactly what a partial write or a botched merge leaves behind.

TOTAL=$((TOTAL+1))
T27=$(mktemp -d); LATE_TMPDIRS+=("$T27"); setup_repo "$T27" docs
idx27=$(grep -c '^- \[id: ' "$T27/AGENTS.md")
grep -v 'cq-test-rest' "$T27/AGENTS.rules.md" > "$T27/AGENTS.rules.md.tmp"
mv "$T27/AGENTS.rules.md.tmp" "$T27/AGENTS.rules.md"
stamp27=$(invoke_hook "$T27" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
num27=$(printf '%s' "$stamp27" | sed -nE 's/.*loaded: ([0-9]+) of [0-9]+ rules.*/\1/p' || true)
den27=$(printf '%s' "$stamp27" | sed -nE 's/.*loaded: [0-9]+ of ([0-9]+) rules.*/\1/p' || true)
if [[ -n "$num27" && -n "$den27" ]] && (( num27 < den27 )) && [[ "$den27" == "$idx27" ]]; then
  echo "PASS: truncated corpus stamps a proper subset ($num27 of $den27, index=$idx27)"
  PASS=$((PASS+1))
else
  echo "FAIL: truncated-corpus numerator/denominator wrong (num=$num27 den=$den27 index=$idx27) — $stamp27"
  FAIL=$((FAIL+1))
fi

# ------------- Test 27b: a MISSING sidecar must not shrink the denominator ----
# The #7008 regression in its most dangerous form: the corpus is gone entirely.
# A denominator derived from what actually loaded would stamp a vacuous "0 of 0";
# the fixed expected set from the index keeps it "0 of N", the blackout signal.

TOTAL=$((TOTAL+1))
T27B=$(mktemp -d); LATE_TMPDIRS+=("$T27B"); setup_repo "$T27B" docs
idx27b=$(grep -c '^- \[id: ' "$T27B/AGENTS.md")
rm -f "$T27B/AGENTS.rules.md"
stamp27b=$(invoke_hook "$T27B" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
den27b=$(printf '%s' "$stamp27b" | sed -nE 's/.*loaded: [0-9]+ of ([0-9]+) rules.*/\1/p' || true)
if [[ "$den27b" == "$idx27b" ]]; then
  echo "PASS: absent corpus leaves the denominator at the declared corpus size ($den27b)"
  PASS=$((PASS+1))
else
  echo "FAIL: denominator collapsed to $den27b (index says $idx27b) — a truncated corpus reads as full: $stamp27b"
  FAIL=$((FAIL+1))
fi

# ------------- Test 28: WORST-CASE composed stamp (both notes) ≤ 200 BYTES ----
# Test 11 measures the happy path with awk's `length` (CHARACTERS). The notes
# carry em-dashes (3 B each), so the real contract needs `wc -c` against the
# composed worst case: all three classes + fail-safe note + over-strip note.

TOTAL=$((TOTAL+1))
T28=$(mktemp -d); LATE_TMPDIRS+=("$T28"); setup_repo "$T28" mixed
# With one corpus the two notes are mutually exclusive (a symlink-rejected corpus
# is never stripped, so the over-strip guard cannot also fire). Measure the
# worst case that is actually REACHABLE: the over-strip note.
printf -- '---\nbroken frontmatter\n# AGENTS Rules\n## Hard Rules\n- Core rule [id: hr-test-core].\n' > "$T28/AGENTS.rules.md"
stamp28=$(invoke_hook "$T28" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
bytes28=$(printf '%s' "$stamp28" | wc -c | tr -d ' ')
if (( bytes28 <= 200 )); then
  echo "PASS: worst-case composed stamp ≤ 200 bytes (${bytes28}B)"
  PASS=$((PASS+1))
else
  echo "FAIL: worst-case composed stamp ${bytes28}B > 200B: $stamp28"
  FAIL=$((FAIL+1))
fi

# ------------- Test 29: fail-safe names its ACTUAL cause ----
# A symlink rejection is a prompt-injection defense firing; reporting it as
# "corpus missing" sends the operator looking for a deleted file (#7008).

TOTAL=$((TOTAL+1))
T29=$(mktemp -d); LATE_TMPDIRS+=("$T29"); setup_repo "$T29" code
rm -f "$T29/AGENTS.rules.md"; ln -s /dev/null "$T29/AGENTS.rules.md"
stamp29=$(invoke_hook "$T29" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
if printf '%s' "$stamp29" | grep -qF 'symlink'; then
  echo "PASS: fail-safe names the symlink rejection, not a phantom missing file"
  PASS=$((PASS+1))
else
  echo "FAIL: symlink rejection reported as: $stamp29"
  FAIL=$((FAIL+1))
fi

# ------------- Test 30: core-only fallback must not claim a load it did not do ----
# When the corpus is itself unreadable the fallback loads NOTHING; saying
# "loaded AGENTS.rules.md only" there is a false claim on the least-visible path.

TOTAL=$((TOTAL+1))
T30=$(mktemp -d); LATE_TMPDIRS+=("$T30")   # deliberately NOT a git repo -> fallback path
out30=$(printf '{"cwd":"%s"}' "$T30" | "$HOOK" 2>/dev/null)
ctx30=$(printf '%s' "$out30" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
# The old assertion accepted a present/absent BOOLEAN ('NO rules loaded'). That
# is too weak: a PARTIAL corpus is 'present', so a 3-of-101 fallback rendered
# byte-identical to a healthy one. Assert the NUMERATOR shape instead, which
# also makes the `loaded: N of M` liveness probe total on this path.
if printf '%s' "$ctx30" | grep -qE 'loaded: 0 of [0-9?]+ rules'; then
  echo "PASS: fallback stamps a 0-of-N numerator when the corpus is unreadable"
  PASS=$((PASS+1))
else
  echo "FAIL: fallback claims a load it did not perform: $ctx30"
  FAIL=$((FAIL+1))
fi

# --- Test 31: the fallback must not render a PARTIAL corpus as a full load ----
# Regression for the shape the boolean missed entirely.
TOTAL=$((TOTAL+1))
T31=$(mktemp -d); LATE_TMPDIRS+=("$T31")   # deliberately NOT a git repo -> fallback
printf '# Index\n## Hard Rules\n- [id: hr-a]\n- [id: hr-b]\n- [id: hr-c]\n' > "$T31/AGENTS.md"
printf '# R\n## Hard Rules\n- one [id: hr-a].\n' > "$T31/AGENTS.rules.md"
ctx31=$(printf '{"cwd":"%s"}' "$T31" | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
if printf '%s' "$ctx31" | grep -qE 'loaded: 1 of 3 rules'; then
  echo "PASS: fallback distinguishes a partial corpus (1 of 3) from a full load"
  PASS=$((PASS+1))
else
  echo "FAIL: fallback did not report the partial count: $ctx31"
  FAIL=$((FAIL+1))
fi

# ------------- Test 32: the corpus is injected IN FULL (ADR-151's core claim) ----
# Nothing else in this suite observes WHAT REACHED CONTEXT. Every other arm reads
# the stamp, and the stamp can be honest about a partial load (`1 of 3`) or, if
# the numerator is ever re-derived from the file on disk instead of from
# $CONTEXT, dishonest about it (`3 of 3` while injecting 1). Both mutations were
# measured to pass the pre-existing 29 arms.
#
# The manifest is the seam that closes it: `rule_ids_loaded` is derived from
# $CONTEXT, so it is a true record of what was injected. Assert it equals the
# AGENTS.md pointer id set — the fixed expected set lint-rule-ids.py already
# couples 1:1 to the bodies.

TOTAL=$((TOTAL+1))
T32=$(mktemp -d); LATE_TMPDIRS+=("$T32"); setup_repo "$T32" mixed
m32=$(invoke_hook "$T32" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null \
        | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
if [[ -z "$m32" || ! -f "$m32" ]]; then
  echo "FAIL: full-injection check could not locate the manifest"
  FAIL=$((FAIL+1))
else
  want32=$(grep -oE '^- \[id: [a-z0-9-]+\]' "$T32/AGENTS.md" | sed -E 's/^- \[id: (.*)\]$/\1/' | sort | tr '\n' ' ')
  got32=$(jq -r '.rule_ids_loaded[]' "$m32" | sort | tr '\n' ' ')
  if [[ "$want32" == "$got32" && -n "$want32" ]]; then
    echo "PASS: every indexed rule id actually reached context ($(printf '%s' "$want32" | wc -w) ids)"
    PASS=$((PASS+1))
  else
    echo "FAIL: injected id set != index id set"
    echo "  index:    $want32"
    echo "  injected: $got32"
    FAIL=$((FAIL+1))
  fi
fi

echo ""
echo "RESULT: $PASS/$TOTAL passed ($FAIL failed)"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
