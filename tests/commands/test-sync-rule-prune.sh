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
        --json)   shift 2 ;;
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
    schema:1,
    generated_at:"2026-04-14T00:00:00Z",
    rules:[
      {id:"hr-never-used-a", section:"Hard Rules", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"Rule A prefix"},
      {id:"hr-never-used-b", section:"Hard Rules", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"Rule B prefix"},
      {id:"cq-used",         section:"Code Quality", hit_count:5, bypass_count:0, applied_count:0, warn_count:0, fire_count:5, prevented_errors:5, last_hit:"2026-04-10T00:00:00Z", first_seen:$seen, rule_text_prefix:"Rule C prefix"}
    ],
    summary:{total_rules_tagged:3, rules_unused_over_8w:2, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
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

# T5: invalid rule_id rejected with stderr warning, no issue filed
t_invalid_rule_id_skipped() {
  local root; root=$(_setup)
  # Inject a malformed id alongside the two valid ones. Mirrors a
  # corruption scenario where rule-metrics.json carries junk from a
  # malformed jsonl or an orphaned id that slipped past parsing.
  local cutoff
  cutoff=$(date -u -d "-70 days" +%Y-%m-%dT%H:%M:%SZ)
  jq --arg seen "$cutoff" '.rules += [
    {id:"has space in id", section:"Hard Rules", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"bad id"}
  ]' "$root/knowledge-base/project/rule-metrics.json" > "$root/tmp.json"
  mv "$root/tmp.json" "$root/knowledge-base/project/rule-metrics.json"

  local err="$root/err.log"
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 2> "$err" >/dev/null
  local n; n=$(ls "$root/issues" 2>/dev/null | wc -l)
  # Expect the two valid rules filed, the invalid one skipped.
  if [[ "$n" == "2" ]] && grep -q 'Skipping invalid rule_id: has space in id' "$err"; then
    _report "rule-prune: invalid rule_id skipped with warning" ok
  else
    _report "rule-prune: invalid rule_id skipped with warning" fail "n=$n; err=$(cat "$err")"
  fi
  rm -rf "$root"
}

# T6: issue body includes Verify block with jq query + generated_at
t_body_has_verify_block() {
  local root; root=$(_setup)
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=8 >/dev/null 2>&1
  local first; first=$(ls "$root/issues"/*.json 2>/dev/null | head -1)
  [[ -n "$first" ]] || { _report "body: at least one issue filed" fail ""; rm -rf "$root"; return; }
  local body; body=$(jq -r .body "$first")
  if echo "$body" | grep -qF '### Verify' \
     && echo "$body" | grep -qF 'jq ' \
     && echo "$body" | grep -qF 'generated at:' \
     && echo "$body" | grep -qF '2026-04-14T00:00:00Z'; then
    _report "rule-prune: body has Verify block + generated_at" ok
  else
    _report "rule-prune: body has Verify block + generated_at" fail "body was: $body"
  fi
  rm -rf "$root"
}

# --- propose-retirement (--propose-retirement) test fixtures ---------------
#
# These tests exercise the quarterly retirement-proposal path (#3120 C2).
# The default _setup() above uses hr-* ids which are filtered by the new
# flag (per plan: hr-* retirement requires lint-rule-ids.py edit, not
# automated). _setup_pr() builds a fixture with non-hr ids the new flag
# CAN propose for retirement, plus a scripts/retired-rule-ids.txt seed
# file at the path the script expects ($RULE_METRICS_ROOT/scripts/...).
_setup_pr() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/knowledge-base/project" "$tmp/scripts"
  local cutoff
  cutoff=$(date -u -d "-200 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    schema:1,
    generated_at:"2026-05-04T00:00:00Z",
    rules:[
      {id:"wg-pr-stale-foo",   section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"WG foo prefix"},
      {id:"cq-pr-stale-bar",   section:"Code Quality",   hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"CQ bar [hook-enforced: guardrails.sh] prefix"},
      {id:"hr-pr-stale-baz",   section:"Hard Rules",     hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"HR baz prefix"},
      {id:"wg-pr-already-ret", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"already-retired prefix"},
      {id:"rf-pr-active",      section:"Review & Feedback", hit_count:9, bypass_count:0, applied_count:0, warn_count:0, fire_count:9, prevented_errors:9, last_hit:"2026-05-01T00:00:00Z", first_seen:$seen, rule_text_prefix:"active rule"}
    ],
    summary:{total_rules_tagged:5, rules_unused_over_8w:4, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$tmp/knowledge-base/project/rule-metrics.json"
  cat > "$tmp/scripts/retired-rule-ids.txt" <<'RETIRED'
# Retired AGENTS.md rule IDs.
#
# Format: <rule-id> | <YYYY-MM-DD> | <PR #NNNN or -> | <breadcrumb>

wg-pr-already-ret | 2026-04-01 | PR #2001 | seeded for test
RETIRED
  echo "$tmp"
}

# Run rule-prune in propose-retirement mode and capture stdout/stderr.
# Defense-in-depth: stub `gh` on PATH even though --propose-retirement
# should not invoke it. Prevents real GitHub issues if the flag falls
# through to the per-rule-issue codepath (e.g., during RED-phase reruns
# or future regressions). _build_fake_gh sets up $root/bin/gh.
_run_pr() {
  local root="$1"; shift
  _build_fake_gh "$root"
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=26 --propose-retirement "$@" \
    > "$root/out.txt" 2> "$root/err.txt"
  echo $?
}

# tp1: no candidates → exit 0, no file mutation, no sentinels emitted.
tp1_no_candidates() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  jq -n '{
    schema:1, generated_at:"2026-05-04T00:00:00Z",
    rules:[{id:"rf-active", section:"Review & Feedback", hit_count:5, bypass_count:0, applied_count:0, warn_count:0, fire_count:5, prevented_errors:5, last_hit:"2026-05-01T00:00:00Z", first_seen:"2026-04-01T00:00:00Z", rule_text_prefix:"x"}],
    summary:{total_rules_tagged:1, rules_unused_over_8w:0, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$root/knowledge-base/project/rule-metrics.json"
  : > "$root/scripts/retired-rule-ids.txt"
  local rc; rc=$(_run_pr "$root")
  # Empty-candidates exits via shared "No prune candidates" path; the
  # propose-retirement-specific "No retirement candidates" fires only
  # when candidates exist but are all filtered (hr-*/already-retired/
  # duplicate). Either is the correct empty-result path; both must
  # exit 0 with no sentinels and no file mutation.
  if [[ "$rc" == "0" ]] \
     && grep -qE 'No (prune|retirement) candidates' "$root/out.txt" \
     && ! grep -qE '::rule-prune-pr-(title|body)::' "$root/out.txt" \
     && ! grep -qE 'wg-|cq-' "$root/scripts/retired-rule-ids.txt"; then
    _report "tp1: no candidates → exit 0, no sentinels, no append" ok
  else
    _report "tp1: no candidates → exit 0, no sentinels, no append" fail "rc=$rc; out=$(cat "$root/out.txt"); file=$(cat "$root/scripts/retired-rule-ids.txt")"
  fi
  rm -rf "$root"
}

# tp2: one non-hr candidate → exactly one append in canonical format,
# both sentinels emitted on stdout.
tp2_one_non_hr() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  local cutoff; cutoff=$(date -u -d "-200 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    schema:1, generated_at:"2026-05-04T00:00:00Z",
    rules:[{id:"wg-stale-only", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"some prefix"}],
    summary:{total_rules_tagged:1, rules_unused_over_8w:1, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$root/knowledge-base/project/rule-metrics.json"
  : > "$root/scripts/retired-rule-ids.txt"
  local rc; rc=$(_run_pr "$root")
  local appends; appends=$(grep -cE '^wg-stale-only \|' "$root/scripts/retired-rule-ids.txt" || echo 0)
  if [[ "$rc" == "0" ]] \
     && [[ "$appends" == "1" ]] \
     && grep -qE '^::rule-prune-pr-title::' "$root/out.txt" \
     && grep -qE '^::rule-prune-pr-body::'  "$root/out.txt"; then
    _report "tp2: one non-hr → 1 append + sentinels" ok
  else
    _report "tp2: one non-hr → 1 append + sentinels" fail "rc=$rc; appends=$appends; out=$(cat "$root/out.txt"); file=$(cat "$root/scripts/retired-rule-ids.txt")"
  fi
  rm -rf "$root"
}

# tp3: hr-* candidate is filtered (NOT appended) regardless of staleness.
tp3_hr_skipped() {
  local root; root=$(_setup_pr)
  local rc; rc=$(_run_pr "$root")
  if [[ "$rc" == "0" ]] \
     && ! grep -qE '^hr-pr-stale-baz \|' "$root/scripts/retired-rule-ids.txt" \
     && grep -qiE '\[skip\].*hr-' "$root/out.txt"; then
    _report "tp3: hr-* candidate skipped" ok
  else
    _report "tp3: hr-* candidate skipped" fail "rc=$rc; out=$(cat "$root/out.txt"); file=$(cat "$root/scripts/retired-rule-ids.txt")"
  fi
  rm -rf "$root"
}

# tp4: id already in retired-rule-ids.txt → no second append, skip log.
tp4_already_retired() {
  local root; root=$(_setup_pr)
  local rc; rc=$(_run_pr "$root")
  local n; n=$(grep -cE '^wg-pr-already-ret \|' "$root/scripts/retired-rule-ids.txt" || echo 0)
  if [[ "$rc" == "0" ]] \
     && [[ "$n" == "1" ]] \
     && grep -qE '\[skip\] already retired' "$root/out.txt"; then
    _report "tp4: already-retired id not re-appended" ok
  else
    _report "tp4: already-retired id not re-appended" fail "rc=$rc; n=$n; out=$(cat "$root/out.txt")"
  fi
  rm -rf "$root"
}

# tp5a: mixed fixture → exactly 2 non-hr appends (wg-pr-stale-foo + cq-pr-stale-bar).
tp5a_mixed_counts() {
  local root; root=$(_setup_pr)
  local rc; rc=$(_run_pr "$root")
  local foo bar
  foo=$(grep -cE '^wg-pr-stale-foo \|' "$root/scripts/retired-rule-ids.txt" || echo 0)
  bar=$(grep -cE '^cq-pr-stale-bar \|' "$root/scripts/retired-rule-ids.txt" || echo 0)
  if [[ "$rc" == "0" ]] && [[ "$foo" == "1" ]] && [[ "$bar" == "1" ]]; then
    _report "tp5a: mixed → both non-hr ids appended exactly once" ok
  else
    _report "tp5a: mixed → both non-hr ids appended exactly once" fail "rc=$rc; foo=$foo; bar=$bar; file=$(cat "$root/scripts/retired-rule-ids.txt")"
  fi
  rm -rf "$root"
}

# tp5b: title sentinel format includes hook-enforced count.
tp5b_title_format() {
  local root; root=$(_setup_pr)
  _run_pr "$root" >/dev/null
  local title
  title=$(grep -E '^::rule-prune-pr-title::' "$root/out.txt" | head -n 1 | sed 's/^::rule-prune-pr-title:://')
  # Expected: "feat(rule-prune): propose retirement of 2 rules (1 hook/skill-enforced)"
  if echo "$title" | grep -qE 'propose retirement of 2 rules' \
     && echo "$title" | grep -qE '\(1 hook/skill-enforced\)'; then
    _report "tp5b: title sentinel format" ok
  else
    _report "tp5b: title sentinel format" fail "title='$title'"
  fi
  rm -rf "$root"
}

# tp8: schema mismatch → exit 3, --propose-retirement does not bypass.
tp8_schema_mismatch() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  jq -n '{schema:99, generated_at:"x", rules:[], summary:{total_rules_tagged:0, rules_unused_over_8w:0, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}}' \
    > "$root/knowledge-base/project/rule-metrics.json"
  _build_fake_gh "$root"
  # Capture non-zero exit without tripping set -e in the parent test script.
  local rc=0
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=26 --propose-retirement \
    > "$root/out.txt" 2> "$root/err.txt" || rc=$?
  if [[ "$rc" == "3" ]] && grep -qE 'unexpected schema' "$root/err.txt"; then
    _report "tp8: schema mismatch → exit 3" ok
  else
    _report "tp8: schema mismatch → exit 3" fail "rc=$rc; err=$(cat "$root/err.txt")"
  fi
  rm -rf "$root"
}

# tp9: re-run idempotency. After tp2-style append, second run sees the id
# in the seed file and skips it.
tp9_rerun_idempotent() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  local cutoff; cutoff=$(date -u -d "-200 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    schema:1, generated_at:"2026-05-04T00:00:00Z",
    rules:[{id:"wg-stale-rerun", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"x"}],
    summary:{total_rules_tagged:1, rules_unused_over_8w:1, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$root/knowledge-base/project/rule-metrics.json"
  : > "$root/scripts/retired-rule-ids.txt"
  _run_pr "$root" >/dev/null
  local lines_after_first; lines_after_first=$(wc -l < "$root/scripts/retired-rule-ids.txt")
  _run_pr "$root" >/dev/null
  local lines_after_second; lines_after_second=$(wc -l < "$root/scripts/retired-rule-ids.txt")
  if [[ "$lines_after_first" == "$lines_after_second" ]] \
     && grep -qE '\[skip\] already retired' "$root/out.txt"; then
    _report "tp9: re-run does not re-append" ok
  else
    _report "tp9: re-run does not re-append" fail "first=$lines_after_first second=$lines_after_second"
  fi
  rm -rf "$root"
}

# tp10: duplicate-id within rule-metrics candidate set → only first appended.
tp10_duplicate_candidate() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  local cutoff; cutoff=$(date -u -d "-200 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    schema:1, generated_at:"2026-05-04T00:00:00Z",
    rules:[
      {id:"wg-dup", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"x"},
      {id:"wg-dup", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"x"}
    ],
    summary:{total_rules_tagged:2, rules_unused_over_8w:2, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$root/knowledge-base/project/rule-metrics.json"
  : > "$root/scripts/retired-rule-ids.txt"
  _run_pr "$root" >/dev/null
  local n; n=$(grep -cE '^wg-dup \|' "$root/scripts/retired-rule-ids.txt" || echo 0)
  if [[ "$n" == "1" ]] && grep -qE '\[skip\] duplicate candidate id' "$root/out.txt"; then
    _report "tp10: duplicate candidate id → single append" ok
  else
    _report "tp10: duplicate candidate id → single append" fail "n=$n; out=$(cat "$root/out.txt")"
  fi
  rm -rf "$root"
}

# tp11: --propose-retirement --dry-run → no file write, sentinels still emitted.
tp11_dry_run_honored() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project" "$root/scripts"
  local cutoff; cutoff=$(date -u -d "-200 days" +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg seen "$cutoff" '{
    schema:1, generated_at:"2026-05-04T00:00:00Z",
    rules:[{id:"wg-dry", section:"Workflow Gates", hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, prevented_errors:0, last_hit:null, first_seen:$seen, rule_text_prefix:"x"}],
    summary:{total_rules_tagged:1, rules_unused_over_8w:1, rules_bypassed_over_baseline:0, orphan_rule_ids:[]}
  }' > "$root/knowledge-base/project/rule-metrics.json"
  : > "$root/scripts/retired-rule-ids.txt"
  _build_fake_gh "$root"
  local rc=0
  PATH="$root/bin:$PATH" FAKE_GH_STATE="$root" RULE_METRICS_ROOT="$root" \
    bash "$SCRIPT" --weeks=26 --propose-retirement --dry-run \
    > "$root/out.txt" 2> "$root/err.txt" || rc=$?
  local n=0
  n=$(grep -cE '^wg-dry \|' "$root/scripts/retired-rule-ids.txt" 2>/dev/null) || n=0
  if [[ "$rc" == "0" ]] && [[ "$n" == "0" ]] \
     && grep -qE '^::rule-prune-pr-title::' "$root/out.txt" \
     && grep -qE '^::rule-prune-pr-body::'  "$root/out.txt"; then
    _report "tp11: --dry-run → no append, sentinels emitted" ok
  else
    _report "tp11: --dry-run → no append, sentinels emitted" fail "rc=$rc; n=$n; out=$(cat "$root/out.txt")"
  fi
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
t_invalid_rule_id_skipped
t_body_has_verify_block

# --propose-retirement (#3120 C2) tests
tp1_no_candidates
tp2_one_non_hr
tp3_hr_skipped
tp4_already_retired
tp5a_mixed_counts
tp5b_title_format
tp8_schema_mismatch
tp9_rerun_idempotent
tp10_duplicate_candidate
tp11_dry_run_honored

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
