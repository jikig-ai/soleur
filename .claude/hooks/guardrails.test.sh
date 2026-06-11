#!/usr/bin/env bash
# Fixture-based tests for guardrails.sh — scoped to the require-milestone gate.
# Asserts gh issue create against OUR repo requires --milestone, while creation
# against an EXTERNAL repo (different owner) is exempt (their milestone sets
# differ; the backlog-hygiene rule applies only to our own issues).
#
# Isolation: the hook is invoked via stdin with synthetic Bash tool payloads;
# no real gh call is made. INCIDENTS_REPO_ROOT redirects emit_incident writes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/guardrails.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

mk_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Returns the permissionDecision or "<none>" when the hook emits no JSON (allow).
decision_of() {
  local cmd="$1" tmp; tmp="$(mktemp -d)"
  local out
  out="$(mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)"
  rm -rf "$tmp"
  # An allow is empty hook output (no JSON emitted); normalize to "<none>".
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert() {
  local label="$1" want="$2" cmd="$3"
  TOTAL=$((TOTAL + 1))
  local got; got="$(decision_of "$cmd")"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# Our repo (implicit) without --milestone → deny.
assert "implicit repo, no milestone denies" "deny" \
  'gh issue create --title "x" --body "y"'

# Our repo (implicit) with --milestone → allow.
assert "implicit repo, with milestone allows" "<none>" \
  'gh issue create --title "x" --body "y" --milestone "Post-MVP / Later"'

# Explicit OUR repo without --milestone → deny (still gated).
assert "explicit jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo jikig-ai/soleur --title "x" --body "y"'

# External repo without --milestone → allow (exempt: different owner).
assert "external repo, no milestone allows" "<none>" \
  'gh issue create --repo highagency/pencil-desktop-releases --title "x" --body-file /tmp/b.md'

# External repo with --repo=owner/name form → allow.
assert "external repo (=form), no milestone allows" "<none>" \
  'gh issue create --repo=highagency/pencil-desktop-releases --title "x"'

# QUOTED our repo without --milestone → deny (quote-aware: must not be read as external).
assert "quoted jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo "jikig-ai/soleur" --title x'

# Embedded --repo string inside a quoted --body, no real --repo → deny (no bypass).
assert "embedded --repo in body, no milestone denies" "deny" \
  'gh issue create --title real --body "see --repo evil/x for context"'

# -R short form targeting OUR repo while an embedded external string sits in title → deny.
assert "short -R our repo wins over embedded external denies" "deny" \
  'gh issue create --title "--repo evil/x" -R jikig-ai/soleur'

# Genuine external via short -R form, no milestone → allow.
assert "external via -R short form allows" "<none>" \
  'gh issue create -R highagency/pencil-desktop-releases --title x'

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
