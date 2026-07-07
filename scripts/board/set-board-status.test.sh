#!/usr/bin/env bash
# Unit test for set-board-status.sh with a mocked `gh` (a new workflow can't be
# workflow_dispatch-tested from a feature branch). Asserts the lifecycle event →
# board Status mapping, incl. the cases Kieran flagged: reopened, PR
# closed-unmerged, blocked-removed recompute, and `Ref #N` PR→issue resolution.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/set-board-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export MOCK_STATE_FILE="$TMP/last-opt"
export GH_TOKEN="mock-token"
export SOLEUR_KANBAN_ORG="jikig-ai"
export SOLEUR_KANBAN_PROJECT_NUMBER="2"

# ---- Mock `gh` on PATH ----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
declare -A KV
args=("$@"); i=0
while [[ $i -lt ${#args[@]} ]]; do
  a="${args[$i]}"
  if [[ "$a" == "-f" || "$a" == "-F" ]]; then
    kv="${args[$((i+1))]}"; KV["${kv%%=*}"]="${kv#*=}"; i=$((i+2))
  else i=$((i+1)); fi
done
q="${KV[query]:-}"
case "$q" in
  *"projectV2(number"*)
    printf '%s' '{"data":{"organization":{"projectV2":{"id":"PVT_1","field":{"id":"PVTF_1","options":[{"id":"OPT_backlog","name":"Backlog"},{"id":"OPT_ready","name":"Ready"},{"id":"OPT_in_progress","name":"In progress"},{"id":"OPT_in_review","name":"In review"},{"id":"OPT_blocked","name":"Blocked"},{"id":"OPT_pending","name":"Pending"},{"id":"OPT_done","name":"Done"}]}}}}}';;
  *"addProjectV2ItemById"*)
    printf '%s' '{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_1"}}}}';;
  *"projectItems"*)
    printf '%s' '{"data":{"node":{"projectItems":{"nodes":[{"id":"PVTI_1","project":{"id":"PVT_1"}}]}}}}';;
  *"updateProjectV2ItemFieldValue"*)
    printf '%s' "${KV[opt]}" > "$MOCK_STATE_FILE"
    printf '%s' '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_1"}}}}';;
  *"fieldValueByName"*)
    opt=$(cat "$MOCK_STATE_FILE" 2>/dev/null || true)
    case "$opt" in
      OPT_backlog) name="Backlog";; OPT_ready) name="Ready";;
      OPT_in_progress) name="In progress";; OPT_in_review) name="In review";;
      OPT_blocked) name="Blocked";; OPT_pending) name="Pending";;
      OPT_done) name="Done";; *) name="";;
    esac
    printf '{"data":{"node":{"fieldValueByName":{"name":"%s"}}}}' "$name";;
  *"timelineItems"*)
    out="${MOCK_ISSUE_JSON:-}"
    [[ -z "$out" ]] && out='{"data":{"node":{"state":"OPEN","labels":{"nodes":[]},"timelineItems":{"nodes":[]}}}}'
    printf '%s' "$out";;
  *"closingIssuesReferences"*)
    out="${MOCK_PR_LINK_JSON:-}"
    [[ -z "$out" ]] && out='{"data":{"node":{"closingIssuesReferences":{"nodes":[]},"repository":{"owner":{"login":"jikig-ai"},"name":"soleur"}}}}'
    printf '%s' "$out";;
  *"repository(owner"*)
    printf '{"data":{"repository":{"issue":{"id":"ISSUE_%s"}}}}' "${KV[n]}";;
  *) echo "MOCK_GH unhandled: $q" >&2; exit 1;;
esac
MOCK
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

PASS=0; FAIL=0
event() { # $1=name $2=json ; sets GITHUB_EVENT_NAME + GITHUB_EVENT_PATH
  export GITHUB_EVENT_NAME="$1"
  printf '%s' "$2" > "$TMP/event.json"
  export GITHUB_EVENT_PATH="$TMP/event.json"
}
run_dispatch() { : > "$MOCK_STATE_FILE"; bash "$SCRIPT" dispatch >/dev/null 2>&1 || true; }
assert_opt() { # $1=expected-opt $2=label
  local got; got=$(cat "$MOCK_STATE_FILE" 2>/dev/null || true)
  if [[ "$got" == "$1" ]]; then PASS=$((PASS+1)); echo "ok   - $2"
  else FAIL=$((FAIL+1)); echo "FAIL - $2 (expected $1, got '${got:-<none>}')"; fi
}

# 1. issue labeled blocked -> Blocked
event issues '{"action":"labeled","issue":{"node_id":"I_1"},"label":{"name":"blocked"}}'
run_dispatch; assert_opt OPT_blocked "issue labeled blocked -> Blocked"

# 2. issue labeled pending -> Pending
event issues '{"action":"labeled","issue":{"node_id":"I_1"},"label":{"name":"pending"}}'
run_dispatch; assert_opt OPT_pending "issue labeled pending -> Pending"

# 3. issue unlabeled blocked (open, no labels, no PR) -> recompute -> Backlog
export MOCK_ISSUE_JSON='{"data":{"node":{"state":"OPEN","labels":{"nodes":[]},"timelineItems":{"nodes":[]}}}}'
event issues '{"action":"unlabeled","issue":{"node_id":"I_1"},"label":{"name":"blocked"}}'
run_dispatch; assert_opt OPT_backlog "issue unlabeled blocked (no PR) -> Backlog"
unset MOCK_ISSUE_JSON

# 4. issue reopened (open, no labels, no PR) -> recompute -> Backlog
event issues '{"action":"reopened","issue":{"node_id":"I_1"}}'
run_dispatch; assert_opt OPT_backlog "issue reopened -> recompute -> Backlog"

# 5. PR opened as DRAFT with `Ref #5875` -> linked issue In progress
event pull_request '{"action":"opened","pull_request":{"node_id":"PR_1","state":"open","draft":true,"merged":false,"body":"Fixes the sandbox. Ref #5875"}}'
run_dispatch; assert_opt OPT_in_progress "PR opened draft (Ref #5875) -> In progress"

# 6. PR ready_for_review (not draft) -> linked issue In review
event pull_request '{"action":"ready_for_review","pull_request":{"node_id":"PR_1","state":"open","draft":false,"merged":false,"body":"Ref #5875"}}'
run_dispatch; assert_opt OPT_in_review "PR ready_for_review -> In review"

# 7. PR closed & NOT merged -> recompute linked issue -> Backlog
export MOCK_ISSUE_JSON='{"data":{"node":{"state":"OPEN","labels":{"nodes":[]},"timelineItems":{"nodes":[]}}}}'
event pull_request '{"action":"closed","pull_request":{"node_id":"PR_1","state":"closed","draft":false,"merged":false,"body":"Ref #5875"}}'
run_dispatch; assert_opt OPT_backlog "PR closed-unmerged -> recompute -> Backlog"
unset MOCK_ISSUE_JSON

# 8. PR merged -> linked issue Done (Ref #N doesn't auto-close, so set explicitly)
event pull_request '{"action":"closed","pull_request":{"node_id":"PR_1","state":"closed","draft":false,"merged":true,"body":"Ref #5875"}}'
run_dispatch; assert_opt OPT_done "PR merged (Ref) -> Done"

# 9. recompute with an OPEN draft PR in the timeline -> In progress
export MOCK_ISSUE_JSON='{"data":{"node":{"state":"OPEN","labels":{"nodes":[]},"timelineItems":{"nodes":[{"source":{"state":"OPEN","isDraft":true}}]}}}}'
event issues '{"action":"reopened","issue":{"node_id":"I_9"}}'
run_dispatch; assert_opt OPT_in_progress "reopened w/ open draft PR -> In progress"
unset MOCK_ISSUE_JSON

# 10. PR merged with `Closes #N` (closingIssuesReferences populated) -> Done
export MOCK_PR_LINK_JSON='{"data":{"node":{"closingIssuesReferences":{"nodes":[{"id":"ISSUE_42"}]},"repository":{"owner":{"login":"jikig-ai"},"name":"soleur"}}}}'
event pull_request '{"action":"closed","pull_request":{"node_id":"PR_2","state":"closed","draft":false,"merged":true,"body":"Closes #42"}}'
run_dispatch; assert_opt OPT_done "PR merged (Closes ref) -> Done"
unset MOCK_PR_LINK_JSON

# 11. PR event with NO linked issue -> clean no-op, exit 0 (regression: the empty
#     `ids` pipeline used to `grep -v '^$'` which exits 1 on zero matches and,
#     under set -euo pipefail, killed the whole script — every PR that links no
#     issue produced a red workflow run). Asserts the real exit code (run_dispatch
#     masks it with `|| true`, which is exactly why the original bug slipped CI).
assert_exit0() { # $1=label ; runs dispatch and asserts a 0 exit
  if bash "$SCRIPT" dispatch >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok   - $1"
  else FAIL=$((FAIL+1)); echo "FAIL - $1 (dispatch exited non-zero)"; fi
}
event pull_request '{"action":"closed","pull_request":{"node_id":"PR_3","state":"closed","draft":false,"merged":true,"body":"No issue linked here."}}'
assert_exit0 "PR merged with no linked issue -> clean exit 0 (no-op)"

echo "-----"
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
