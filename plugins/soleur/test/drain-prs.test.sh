#!/usr/bin/env bash

# Tests for drain-prs helper script (triage-prs.sh).
# Run: bash plugins/soleur/test/drain-prs.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/plugins/soleur/skills/drain-prs/scripts/triage-prs.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/drain-prs"

echo "=== drain-prs triage-prs ==="
echo ""

assert_file_exists "$HELPER" "helper script exists"

# Helper: tier of a PR number in the --format json output.
tier_of() { # $1=json $2=number
  jq -r --argjson n "$2" 'to_entries[] | select(.value[]?.number == $n) | .key' <<<"$1"
}

# ---------------------------------------------------------------------------
# T1 — every tier gets its one synthetic PR (one PR per tier fixture)
# ---------------------------------------------------------------------------
echo ""
echo "--- T1: per-tier classification ---"
json=$(bash "$HELPER" --fixture "$FIXTURE_DIR/all-tiers.json" --format json)

assert_eq "ready-green"                "$(tier_of "$json" 9001)" "9001 → ready-green"
assert_eq "needs-lockfile-fix"         "$(tier_of "$json" 9002)" "9002 → needs-lockfile-fix (deps + failing check)"
assert_eq "needs-conflict-resolution"  "$(tier_of "$json" 9003)" "9003 → needs-conflict-resolution (CONFLICTING)"
assert_eq "needs-review"               "$(tier_of "$json" 9004)" "9004 → needs-review (bot-fix/review-required)"
assert_eq "drafts"                     "$(tier_of "$json" 9005)" "9005 → drafts (isDraft)"
assert_eq "broken"                     "$(tier_of "$json" 9006)" "9006 → broken (CONFLICTING + 3 failing)"

# ---------------------------------------------------------------------------
# T2 — JSON output shape: all six tier keys present, in stable order
# ---------------------------------------------------------------------------
echo ""
echo "--- T2: tier-grouped JSON output shape ---"
keys=$(jq -r 'keys_unsorted | join(",")' <<<"$json")
assert_eq "ready-green,ready-unarmed,needs-lockfile-fix,needs-conflict-resolution,needs-review,broken,drafts" \
  "$keys" "json keys present in stable order"

# ---------------------------------------------------------------------------
# T3 — drafts are isolated (never co-classified with a mergeable tier)
# ---------------------------------------------------------------------------
echo ""
echo "--- T3: drafts isolated ---"
draft_count=$(jq -r '.drafts | length' <<<"$json")
assert_eq "1" "$draft_count" "exactly one draft, kept out of mergeable tiers"

# ---------------------------------------------------------------------------
# T4 — empty PR list → all tiers empty, exit 0
# ---------------------------------------------------------------------------
echo ""
echo "--- T4: empty list ---"
set +e
empty_json=$(bash "$HELPER" --fixture "$FIXTURE_DIR/empty.json" --format json)
rc=$?
set -e
assert_eq "0" "$rc" "empty: exits 0"
assert_eq "0" "$(jq -r '[.[] | length] | add // 0' <<<"$empty_json")" "empty: zero PRs across all tiers"

# ---------------------------------------------------------------------------
# T5 — text format renders a per-tier header with counts
# ---------------------------------------------------------------------------
echo ""
echo "--- T5: text format ---"
text=$(bash "$HELPER" --fixture "$FIXTURE_DIR/all-tiers.json" --format text)
assert_contains "$text" "Open PRs: 6"          "text: reports total open count"
assert_contains "$text" "## ready-green (1)"   "text: ready-green header with count"
assert_contains "$text" "## drafts (1)"        "text: drafts header with count"
assert_contains "$text" "#9001"                "text: lists a PR number"

# ---------------------------------------------------------------------------
# T6 — missing fixture exits non-zero with a readable error
# ---------------------------------------------------------------------------
echo ""
echo "--- T6: missing fixture fails fast ---"
set +e
err=$(bash "$HELPER" --fixture "$FIXTURE_DIR/does-not-exist.json" 2>&1)
rc=$?
set -e
assert_eq "1" "$rc" "missing fixture: exits 1"
assert_contains "$err" "fixture not found" "missing fixture: prints readable error"


# ---------------------------------------------------------------------------
# T7 — ADR-276 S3 (#9728): a ready PR whose newest `test` row is the draft-era red one
#      is classified from ci-head-verdict.sh, never from the rollup's stale red row.
#      The resolver is stubbed through CI_HEAD_VERDICT_BIN (a test seam; live mode calls
#      the real script), answering from ready-verdicts-states.json and logging each call.
# ---------------------------------------------------------------------------
echo ""
echo "--- T7: ready PRs and the head verdict ---"
VTMP="$(mktemp -d)"
trap 'rm -rf "$VTMP"' EXIT
cat > "$VTMP/verdict.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VLOG"
[[ "$1" == verdict && "$2" =~ ^[0-9]+$ ]] || exit 2
st="$(jq -r --arg n "$2" '.[$n] // empty' "$VMAP")"
# The REAL error shape: a marker with state=error (outside the six-state set) AND exit 3, as ci-head-verdict.sh prints it.
[[ -n "$st" && "$st" != "error" ]] || { printf 'SOLEUR_CI_HEAD_VERDICT state=error pr=%s sha=x run=none reason=api-error\n' "$2"; exit 3; }
printf 'SOLEUR_CI_HEAD_VERDICT state=%s pr=%s sha=x run=none reason=stub\n' "$st" "$2"
STUB
chmod +x "$VTMP/verdict.sh"
export VLOG="$VTMP/calls" VMAP="$FIXTURE_DIR/ready-verdicts-states.json"
: > "$VLOG"
vjson=$(CI_HEAD_VERDICT_BIN="$VTMP/verdict.sh" bash "$HELPER" --fixture "$FIXTURE_DIR/ready-verdicts.json" --format json)

assert_eq "ready-green"                "$(tier_of "$vjson" 9101)" "9101 pending-full: the draft-era red test is not counted failing → ready-green"
assert_eq "ready-unarmed"              "$(tier_of "$vjson" 9102)" "9102 no-run: readied but unarmed → ready-unarmed"
assert_eq "ready-unarmed"              "$(tier_of "$vjson" 9103)" "9103 stalled: readied but unarmed → ready-unarmed"
assert_eq "ready-green"                "$(tier_of "$vjson" 9104)" "9104 full-decided: the newest test row (green) wins over the older red one → ready-green"
assert_eq "needs-review"               "$(tier_of "$vjson" 9105)" "9105 full-decided real red test stays failing → not ready-green"
assert_eq "needs-review"               "$(tier_of "$vjson" 9106)" "9106 awaiting-approval is never ready-green"
assert_eq "needs-review"               "$(tier_of "$vjson" 9107)" "9107 n/a red test is today's reading (failing)"
assert_eq "drafts"                     "$(tier_of "$vjson" 9108)" "9108 draft stays a draft whatever its test row says"
assert_eq "needs-conflict-resolution"  "$(tier_of "$vjson" 9109)" "9109 conflicting outranks ready-unarmed"
assert_eq "needs-lockfile-fix"         "$(tier_of "$vjson" 9110)" "9110 a real failure beside a pending-full test keeps its fix tier"
assert_eq "ready-green"                "$(tier_of "$vjson" 9111)" "9111 green control"
assert_eq "0" "$(jq -r '[.["ready-green"][] | select(.number == 9101 or .number == 9104) | .failing] | add' <<<"$vjson")" "pending-full / decided PRs report failing=0"
assert_eq "1" "$(jq -r '.["needs-lockfile-fix"][] | select(.number == 9110) | .failing' <<<"$vjson")" "9110 failing counts only the real lockfile-sync failure"
assert_eq "ready-green,ready-unarmed,needs-lockfile-fix,needs-conflict-resolution,needs-review,broken,drafts" \
  "$(jq -r 'keys_unsorted | join(",")' <<<"$vjson")" "seven tier keys in stable order, ready-unarmed second"

# The resolver is asked ONLY for non-draft PRs that carry a failing test row, once each, with the verdict subcommand.
assert_eq "9101 9102 9103 9105 9106 9107 9109 9110" \
  "$(sed -n 's/^verdict //p' "$VLOG" | sort -n | paste -sd' ' -)" "resolver called for exactly the non-draft PRs whose NEWEST test row is failing (not 9104, whose newest test row is green)"
assert_eq "0" "$(grep -c '^verdict 9108$\|^verdict 9111$' "$VLOG" || true)" "no call for the draft (9108) or the green PR (9111)"

# Recovery command on the unarmed tier (text and json).
vtext=$(CI_HEAD_VERDICT_BIN="$VTMP/verdict.sh" bash "$HELPER" --fixture "$FIXTURE_DIR/ready-verdicts.json" --format text)
assert_contains "$vtext" "## ready-unarmed (2)" "text: ready-unarmed header with its count"
assert_contains "$vtext" "gh pr ready --undo 9102" "text: the recovery command names the PR (undo)"
assert_contains "$vtext" "gh pr ready 9102" "text: the recovery command names the PR (ready again)"
assert_contains "$(jq -r '.["ready-unarmed"][] | select(.number == 9103) | .recovery' <<<"$vjson")" "gh pr ready --undo 9103" "json: ready-unarmed carries the recovery command"

# A resolver that errors falls back to today's reading (the rollup's red test counts), never to a softer one.
: > "$VLOG"
echo '{}' > "$VTMP/errmap.json"
ejson=$(VMAP="$VTMP/errmap.json" CI_HEAD_VERDICT_BIN="$VTMP/verdict.sh" bash "$HELPER" --fixture "$FIXTURE_DIR/ready-verdicts.json" --format json)
assert_eq "needs-review" "$(tier_of "$ejson" 9101)" "resolver error: 9101 keeps today's reading (failing test → not ready-green)"
assert_eq "needs-review" "$(tier_of "$ejson" 9102)" "resolver error: 9102 is not promoted to ready-unarmed or ready-green"
assert_eq "needs-review" "$(tier_of "$ejson" 9103)" "resolver error: a real red test is never read as stalled/ready-unarmed (the api-error marker is not a state)"
assert_eq "0" "$(jq -r '.["ready-unarmed"] | length' <<<"$ejson")" "resolver error: nothing is tiered ready-unarmed, so no PR is told to be un-readied during an outage"

# Without the seam and with --fixture, the resolver is never called (fixture mode is offline).
: > "$VLOG"
(unset CI_HEAD_VERDICT_BIN; bash "$HELPER" --fixture "$FIXTURE_DIR/all-tiers.json" --format json >/dev/null)
assert_eq "0" "$(wc -l < "$VLOG")" "fixture mode without the seam never calls a resolver"

# Live mode (no --fixture, no seam) runs the REAL resolver from the script's own directory: a stub gh serves the PR list and
# refuses everything else, so the resolver errors (state=error) and every PR keeps today's reading. The assertion that
# matters is that the resolver WAS reached through the default path (its PR read shows in the gh log).
echo ""
echo "--- T8: live mode reaches the resolver by its default path ---"
mkdir -p "$VTMP/live-bin"
cat > "$VTMP/live-bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VLOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr list") cat "$LIVE_FIXTURE" ;;
  *) echo "stub gh: refused $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$VTMP/live-bin/gh"
: > "$VLOG"
ljson=$(LIVE_FIXTURE="$FIXTURE_DIR/ready-verdicts.json" PATH="$VTMP/live-bin:$PATH" bash -c 'unset CI_HEAD_VERDICT_BIN; bash "$0" --format json' "$HELPER")
assert_eq "needs-review" "$(tier_of "$ljson" 9105)" "live mode: an outage in the real resolver keeps today's reading (9105 failing test)"
assert_contains "$(cat "$VLOG")" "api -i repos/{owner}/{repo}/pulls/9105" "live mode: the real ci-head-verdict.sh was reached by its default path"

# T9 — the newest row per check is keyed on workflow AND name (a newer green in another workflow must not hide a red).
echo ""
echo "--- T9: newest row per (workflow, check) ---"
wjson=$(bash "$HELPER" --fixture "$FIXTURE_DIR/newest-by-workflow.json" --format json)
assert_eq "needs-review" "$(tier_of "$wjson" 9201)" "9201: same check name in two workflows, the older red still counts → not ready-green"
assert_eq "1" "$(jq -r '.["needs-review"][] | select(.number == 9201) | .failing' <<<"$wjson")" "9201 failing=1"
assert_eq "ready-green" "$(tier_of "$wjson" 9202)" "9202: a rerun of the same workflow check, the newer green decides → ready-green"

print_results 47
