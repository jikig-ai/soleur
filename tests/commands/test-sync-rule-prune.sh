#!/usr/bin/env bash
# Tests for scripts/rule-prune.sh (the executable backend called by
# /soleur:sync rule-prune). Uses a fake `gh` on PATH so issue filing is
# deterministic without network access.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/rule-prune.sh"
pass=0; fail=0

_report() {
  if [[ "$2" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $1"
  else
    fail=$((fail + 1))
    echo "[FAIL] $1 ${3:-}" >&2
  fi
}

# Fake gh: issue list → returns files under $FAKE_GH_STATE/issues/<sha>.json
# matching --search predicate; issue create → writes a new file; issue view
# unused.
_build_fake_gh() {
  local fake="$1"
  mkdir -p "$fake/bin" "$fake/issues"
  cat > "$fake/bin/gh" <<'GH'
#!/usr/bin/env bash
STATE="${FAKE_GH_STATE:?}"
mkdir -p "$STATE/issues"
case "$1 $2" in
  "issue list")
    shift 2
    search=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --search) search="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    # Emit [{number, title}] for any cached issues whose title matches the
    # search predicate ('rule-prune: consider retiring <id> in:title').
    pattern=$(echo "$search" | sed -E 's/ in:title$//')
    ls "$STATE/issues"/*.json 2>/dev/null \
      | while read -r f; do
          title=$(jq -r .title "$f")
          if [[ "$title" == *"$pattern"* ]]; then
            cat "$f"
          fi
        done \
      | jq -s '[.[] | {number: .number, title: .title}]'
    ;;
  "issue create")
    shift 2
    title="" body="" milestone=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title)     title="$2"; shift 2 ;;
        --body)      body="$2"; shift 2 ;;
        --body-file) body="$(cat "$2")"; shift 2 ;;
        --milestone) milestone="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    n=$(( $(ls "$STATE/issues" 2>/dev/null | wc -l) + 1 ))
    jq -n --argjson n "$n" --arg t "$title" --arg b "$body" --arg m "$milestone" \
      '{number:$n, title:$t, body:$b, milestone:$m}' \
      > "$STATE/issues/$(printf '%04d' "$n").json"
    echo "https://example/issues/$n"
    ;;
  *)
    echo "gh stub: unsupported command: $*" >&2
    exit 1
    ;;
esac
GH
  chmod +x "$fake/bin/gh"
}

_setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/knowledge-base/project"
  # Fixture: 2 zero-hit rules older than 8w + 1 hit rule
  local cutoff
  cutoff=$(date -u -d "-70 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    generated_at:"2026-04-14T00:00:00Z",
    rules:[
      {id:"hr-never-used-a", section:"Hard Rules", hit_count:0, bypass_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"Rule A prefix"},
      {id:"hr-never-used-b", section:"Hard Rules", hit_count:0, bypass_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"Rule B prefix"},
      {id:"cq-used",         section:"Code Quality", hit_count:5, bypass_count:0, prevented_errors:5, last_hit:"2026-04-10T00:00:00Z", first_seen:$seen, rule_text_prefix:"Rule C prefix"}
    ],
    summary:{total_rules_tagged:3, rules_unused_over_8w:2, rules_bypassed_over_baseline:0}
  }' > "$tmp/knowledge-base/project/rule-metrics.json"
  _build_fake_gh "$tmp"
  echo "$tmp"
}

# T1: 2 candidates at threshold 8w → 2 issues filed
t_files_issues() {
  local root; root=$(_setup)
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 >/dev/null 2>&1 \
    || { _report "rule-prune files issues" fail "non-zero exit"; rm -rf "$root"; return; }
  local n; n=$(ls "$root/issues" 2>/dev/null | wc -l)
  [[ "$n" == "2" ]] && _report "rule-prune files 2 issues" ok \
    || _report "rule-prune files 2 issues" fail "got $n"
  rm -rf "$root"
}

# T2: re-run → 0 new issues (idempotent via gh issue list match)
t_idempotent() {
  local root; root=$(_setup)
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 >/dev/null 2>&1
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 >/dev/null 2>&1
  local n; n=$(ls "$root/issues" 2>/dev/null | wc -l)
  [[ "$n" == "2" ]] && _report "rule-prune idempotent on re-run" ok \
    || _report "rule-prune idempotent on re-run" fail "expected 2, got $n"
  rm -rf "$root"
}

# T3: --dry-run does not file any issue
t_dry_run() {
  local root; root=$(_setup)
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 --dry-run > "$root/out.txt" 2>&1
  local n; n=$(ls "$root/issues" 2>/dev/null | wc -l)
  [[ "$n" == "0" ]] && _report "rule-prune --dry-run files 0 issues" ok \
    || _report "rule-prune --dry-run files 0 issues" fail "got $n"
  grep -q "Would file 2" "$root/out.txt" \
    && _report "rule-prune --dry-run reports candidate count" ok \
    || _report "rule-prune --dry-run reports candidate count" fail "$(cat "$root/out.txt")"
  rm -rf "$root"
}

# T4: --weeks=0 + all zero-hit → files issues even if first_seen is recent
t_weeks_zero() {
  local root; root=$(_setup)
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=0 >/dev/null 2>&1
  local n; n=$(ls "$root/issues" 2>/dev/null | wc -l)
  [[ "$n" == "2" ]] && _report "--weeks=0 treats all zero-hit as candidates" ok \
    || _report "--weeks=0 treats all zero-hit as candidates" fail "got $n"
  rm -rf "$root"
}

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2
  exit 1
fi

t_files_issues
t_idempotent
t_dry_run
t_weeks_zero

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
