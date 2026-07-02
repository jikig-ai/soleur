#!/usr/bin/env bash
# Single writer for the canonical GitHub Project v2 board "Soleur Kanban" Status
# field (ADR-075). Moves the LINKED ISSUE's card (the Workstream tab reads
# issues, not PRs) as issues/PRs move through their lifecycle.
#
# All board logic lives here (not in the workflow YAML) so it is unit-testable
# with a mocked `gh` — a new workflow cannot be workflow_dispatch-tested from a
# feature branch (learning 2026-04-21-workflow-dispatch-requires-default-branch).
#
# Usage:
#   set-board-status.sh dispatch            # read $GITHUB_EVENT_NAME + $GITHUB_EVENT_PATH
#   set-board-status.sh set-issue <issue-node-id> <StatusName>
#   set-board-status.sh recompute-issue <issue-node-id>
#
# Env:
#   GH_TOKEN                     App installation token w/ org organization_projects:write
#   SOLEUR_KANBAN_ORG            default: jikig-ai
#   SOLEUR_KANBAN_PROJECT_NUMBER default: 2
#   SOLEUR_KANBAN_STATUS_FIELD   default: Status
#
# Two-phase GraphQL (discover ids ONCE, then mutate) keeps every request small,
# avoiding the 500k-node cost cap (learning 2026-05-11-gh-graphql-cost-cap...).
# Every mutation is RE-READ and verified — GitHub returns 200 without applying
# (learning 2026-04-10-github-security-enablement-api-patterns).
set -euo pipefail

ORG="${SOLEUR_KANBAN_ORG:-jikig-ai}"
PROJECT_NUMBER="${SOLEUR_KANBAN_PROJECT_NUMBER:-2}"
STATUS_FIELD="${SOLEUR_KANBAN_STATUS_FIELD:-Status}"

# Board Status option names — MUST match the board's Status single-select values
# verbatim (case-sensitive): "In progress"/"In review" are lowercase p/r.
STATUS_BACKLOG="Backlog"
STATUS_READY="Ready"
STATUS_IN_PROGRESS="In progress"
STATUS_IN_REVIEW="In review"
STATUS_BLOCKED="Blocked"
STATUS_PENDING="Pending"
STATUS_DONE="Done"

log() { printf '%s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

valid_node_id() { [[ "$1" =~ ^[A-Za-z0-9_=-]+$ ]]; }

gql() {
  local query="$1"; shift
  gh api graphql -f query="$query" "$@"
}

# ---- Discovery (one query: project id + Status field id + option id map) ----
PROJECT_JSON=""
discover() {
  [[ -n "$PROJECT_JSON" ]] && return 0
  local q='query($org:String!,$num:Int!,$field:String!){organization(login:$org){projectV2(number:$num){id field(name:$field){... on ProjectV2SingleSelectField{id options{id name}}}}}}'
  PROJECT_JSON=$(gql "$q" -f org="$ORG" -F num="$PROJECT_NUMBER" -f field="$STATUS_FIELD")
  local pid
  pid=$(jq -r '.data.organization.projectV2.id // empty' <<<"$PROJECT_JSON")
  [[ -n "$pid" ]] || die "could not resolve project $ORG/#$PROJECT_NUMBER (token lacks organization_projects, or project moved?)"
}

project_id() { jq -r '.data.organization.projectV2.id' <<<"$PROJECT_JSON"; }
field_id()   { jq -r '.data.organization.projectV2.field.id' <<<"$PROJECT_JSON"; }
option_id_for() {
  jq -r --arg n "$1" '.data.organization.projectV2.field.options[] | select(.name==$n) | .id' <<<"$PROJECT_JSON" | head -1
}

# ---- Ensure a content (issue/PR) is a board item; return its item id ----
ensure_item() {
  local content_id="$1"
  local q='query($id:ID!){node(id:$id){__typename ... on Issue{projectItems(first:20){nodes{id project{id}}}} ... on PullRequest{projectItems(first:20){nodes{id project{id}}}}}}'
  local resp item_id pid
  resp=$(gql "$q" -f id="$content_id")
  pid=$(project_id)
  item_id=$(jq -r --arg pid "$pid" '((.data.node.projectItems.nodes // [])[] | select(.project.id==$pid) | .id) // empty' <<<"$resp" | head -1)
  if [[ -z "$item_id" ]]; then
    local m='mutation($proj:ID!,$content:ID!){addProjectV2ItemById(input:{projectId:$proj,contentId:$content}){item{id}}}'
    item_id=$(gql "$m" -f proj="$pid" -f content="$content_id" | jq -r '.data.addProjectV2ItemById.item.id // empty')
  fi
  [[ -n "$item_id" ]] || die "could not resolve project item for $content_id"
  printf '%s' "$item_id"
}

# ---- Core primitive: set an issue/PR card to a named Status + verify ----
set_issue() {
  local content_id="$1" status_name="$2"
  valid_node_id "$content_id" || die "invalid node id: $content_id"
  discover
  local opt_id
  opt_id=$(option_id_for "$status_name")
  [[ -n "$opt_id" ]] || die "board has no Status option named '$status_name' (column renamed/removed? drift)"
  local item_id fid pid
  item_id=$(ensure_item "$content_id")
  fid=$(field_id); pid=$(project_id)
  local m='mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$opt}}){projectV2Item{id}}}'
  gql "$m" -f proj="$pid" -f item="$item_id" -f field="$fid" -f opt="$opt_id" >/dev/null
  # Re-read + verify (GitHub can 200 without applying).
  local vq='query($id:ID!,$field:String!){node(id:$id){... on ProjectV2Item{fieldValueByName(name:$field){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}'
  local applied
  applied=$(gql "$vq" -f id="$item_id" -f field="$STATUS_FIELD" | jq -r '.data.node.fieldValueByName.name // empty')
  [[ "$applied" == "$status_name" ]] || die "verify failed for $item_id: expected '$status_name', got '$applied'"
  log "OK: $content_id -> $status_name"
}

# ---- Derive the correct OPEN-issue Status from current GitHub state ----
# closed -> Done; blocked/pending label -> Blocked/Pending; open linked PR ->
# In review (ready) / In progress (draft); ready|todo label -> Ready; else Backlog.
recompute_issue() {
  local issue_id="$1"
  valid_node_id "$issue_id" || die "invalid node id: $issue_id"
  local q='query($id:ID!){node(id:$id){... on Issue{state labels(first:50){nodes{name}} timelineItems(itemTypes:[CROSS_REFERENCED_EVENT],first:50){nodes{... on CrossReferencedEvent{source{... on PullRequest{state isDraft}}}}}}}}'
  local resp state labels pr_state
  resp=$(gql "$q" -f id="$issue_id")
  state=$(jq -r '.data.node.state // "OPEN"' <<<"$resp")
  if [[ "$state" == "CLOSED" ]]; then set_issue "$issue_id" "$STATUS_DONE"; return; fi
  labels=$(jq -r '.data.node.labels.nodes[]?.name' <<<"$resp")
  has() { printf '%s\n' "$labels" | grep -qx "$1"; }
  if has "blocked"; then set_issue "$issue_id" "$STATUS_BLOCKED"; return; fi
  if has "pending"; then set_issue "$issue_id" "$STATUS_PENDING"; return; fi
  # Open linked PR (cross-reference) decides In review vs In progress.
  pr_state=$(jq -r '
    [.data.node.timelineItems.nodes[]? | .source? // empty | select(.state=="OPEN")]
    | if length==0 then "none" elif any(.[]; .isDraft==false) then "ready" else "draft" end
  ' <<<"$resp" 2>/dev/null || echo "none")
  case "$pr_state" in
    ready) set_issue "$issue_id" "$STATUS_IN_REVIEW"; return;;
    draft) set_issue "$issue_id" "$STATUS_IN_PROGRESS"; return;;
  esac
  if has "ready" || has "todo"; then set_issue "$issue_id" "$STATUS_READY"; return; fi
  if has "in-progress"; then set_issue "$issue_id" "$STATUS_IN_PROGRESS"; return; fi
  if has "review" || has "needs-review"; then set_issue "$issue_id" "$STATUS_IN_REVIEW"; return; fi
  set_issue "$issue_id" "$STATUS_BACKLOG"
}

# ---- Resolve the issues a PR is linked to: closingIssuesReferences U `Ref #N` ----
# Soleur bot PRs use `Ref #N` (NOT Closes/Fixes), so closingIssuesReferences is
# usually empty — the `Ref #N` body parse is load-bearing (fix-issue SKILL:199).
resolve_linked_issues() {
  local pr_id="$1" body="${2:-}"
  local q='query($id:ID!){node(id:$id){... on PullRequest{closingIssuesReferences(first:20){nodes{id}} repository{owner{login} name}}}}'
  local resp owner repo closing ids n iq iid
  resp=$(gql "$q" -f id="$pr_id")
  owner=$(jq -r '.data.node.repository.owner.login // empty' <<<"$resp")
  repo=$(jq -r '.data.node.repository.name // empty' <<<"$resp")
  closing=$(jq -r '.data.node.closingIssuesReferences.nodes[]?.id' <<<"$resp")
  ids="$closing"
  # `Ref #123`, `Ref: #123`, `ref #123` — tolerate up to 3 chars between.
  for n in $(printf '%s\n' "$body" | grep -oiE 'ref[^0-9]{0,3}#[0-9]+' | grep -oE '[0-9]+' | sort -un); do
    if [[ -n "$owner" && -n "$repo" ]]; then
      iq='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id}}}'
      iid=$(gql "$iq" -f o="$owner" -f r="$repo" -F n="$n" | jq -r '.data.repository.issue.id // empty')
      [[ -n "$iid" ]] && ids+=$'\n'"$iid"
    fi
  done
  printf '%s\n' "$ids" | grep -v '^$' | sort -u
}

# ---- PR event -> move each linked issue ----
from_pr() {
  local payload="$1"
  local pr_id pr_state is_draft merged body linked target iid
  pr_id=$(jq -r '.pull_request.node_id // empty' <<<"$payload")
  [[ -n "$pr_id" ]] || die "PR event missing node_id"
  pr_state=$(jq -r '.pull_request.state // "open"' <<<"$payload")
  is_draft=$(jq -r '.pull_request.draft // false' <<<"$payload")
  merged=$(jq -r '.pull_request.merged // false' <<<"$payload")
  body=$(jq -r '.pull_request.body // ""' <<<"$payload")
  linked=$(resolve_linked_issues "$pr_id" "$body")
  if [[ -z "$linked" ]]; then log "no linked issues for PR $pr_id — nothing to move"; return 0; fi
  if [[ "$pr_state" == "open" ]]; then
    if [[ "$is_draft" == "true" ]]; then target="$STATUS_IN_PROGRESS"; else target="$STATUS_IN_REVIEW"; fi
    while IFS= read -r iid; do [[ -n "$iid" ]] && set_issue "$iid" "$target"; done <<<"$linked"
  elif [[ "$merged" == "true" ]]; then
    # `Ref #N` PRs do NOT auto-close the issue, so the built-in "closed->Done"
    # never fires — set Done explicitly. (A `Closes` PR closes the issue too, and
    # setting Done here is idempotent with the built-in.)
    while IFS= read -r iid; do [[ -n "$iid" ]] && set_issue "$iid" "$STATUS_DONE"; done <<<"$linked"
  else
    # closed & NOT merged (abandoned) — recompute so the issue leaves In review.
    while IFS= read -r iid; do [[ -n "$iid" ]] && recompute_issue "$iid"; done <<<"$linked"
  fi
}

# ---- Dispatch from a GitHub Actions event payload ----
dispatch() {
  local event="${GITHUB_EVENT_NAME:-}"
  local path="${GITHUB_EVENT_PATH:-}"
  [[ -n "$event" && -f "$path" ]] || die "dispatch needs GITHUB_EVENT_NAME + GITHUB_EVENT_PATH"
  local payload; payload=$(cat "$path")
  local action; action=$(jq -r '.action // ""' <<<"$payload")
  case "$event" in
    issues)
      local issue_id label
      issue_id=$(jq -r '.issue.node_id // empty' <<<"$payload")
      [[ -n "$issue_id" ]] || die "issues event missing issue.node_id"
      case "$action" in
        labeled)
          label=$(jq -r '.label.name // ""' <<<"$payload")
          case "$label" in
            blocked) set_issue "$issue_id" "$STATUS_BLOCKED";;
            pending) set_issue "$issue_id" "$STATUS_PENDING";;
            *) log "ignoring label '$label'";;
          esac;;
        unlabeled)
          label=$(jq -r '.label.name // ""' <<<"$payload")
          case "$label" in
            blocked|pending) recompute_issue "$issue_id";;
            *) log "ignoring unlabel '$label'";;
          esac;;
        reopened) recompute_issue "$issue_id";;
        *) log "ignoring issues action '$action'";;
      esac;;
    pull_request) from_pr "$payload";;
    *) log "ignoring event '$event'";;
  esac
}

main() {
  local cmd="${1:-dispatch}"
  case "$cmd" in
    dispatch) dispatch;;
    set-issue) shift; set_issue "$@";;
    recompute-issue) shift; recompute_issue "$@";;
    resolve-linked) shift; resolve_linked_issues "$@";;
    *) die "unknown command: $cmd";;
  esac
}

main "$@"
