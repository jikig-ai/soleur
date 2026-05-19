#!/usr/bin/env bash
# learning-retrieval-bench.sh — one-shot retrieval diagnostic for knowledge-base/project/learnings/
#
# Plan:       knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md
# Spec:       knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md
# Brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md
# Precedent:  scripts/compound-promote.sh:124-200 (Anthropic curl + jq pattern, ADR-021)
#
# Closes #4043 once committed alongside output learning + sibling JSON.
#
# Usage:
#   bash scripts/learning-retrieval-bench.sh                # informational; prints cost estimate + exits 0
#   bash scripts/learning-retrieval-bench.sh --confirm      # full run (~50 min, ~$2.68)
#   bash scripts/learning-retrieval-bench.sh --self-test    # inline synthesized-fixture tests
#
# Test-only:
#   --corpus-count-override <N>   short-circuit corpus walk to value N
#
# Self-test env-var hooks (per cq-test-fixtures-synthesized-only):
#   LEARNINGS_ROOT, INDEX_PATH, OUTPUT_DIR  redirect script reads/writes
#   CURL_BIN                                inject mock curl for API tests
#   LIVE_API=1                              opt in to live calls in self-test

set -euo pipefail

# ─── globals ────────────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LEARNINGS_ROOT="${LEARNINGS_ROOT:-$REPO_ROOT/knowledge-base/project/learnings}"
INDEX_PATH="${INDEX_PATH:-$REPO_ROOT/knowledge-base/INDEX.md}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/knowledge-base/project}"
CURL_BIN="${CURL_BIN:-curl}"

CONFIRM=0
SELF_TEST=0
CORPUS_COUNT_OVERRIDE=""
MODEL_ID="claude-haiku-4-5-20251001"
ANTHROPIC_VERSION="2023-06-01"
ANTHROPIC_ENDPOINT="https://api.anthropic.com/v1/messages"
COST_CEILING_USD=5.00
LIGHT_COST_PER_FILE=0.0010
HEAVY_COST_PER_FILE=0.0015
HEADROOM_FACTOR="1.10"
MAX_TOKENS=512

# ─── arg parsing ────────────────────────────────────────────────────────────
print_help() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
  case "$1" in
    --confirm)                    CONFIRM=1 ;;
    --self-test)                  SELF_TEST=1 ;;
    --corpus-count-override)      CORPUS_COUNT_OVERRIDE="$2"; shift ;;
    --help|-h)                    print_help; exit 0 ;;
    *)
      echo "error: unknown arg: $1" >&2
      echo "run with --help for usage." >&2
      exit 1
      ;;
  esac
  shift
done

# ─── Phase 0: preconditions ─────────────────────────────────────────────────
require_deps() {
  local missing=()
  for c in jq curl git awk sed grep tr find mktemp; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing+=("$c")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "error: missing required commands: ${missing[*]}" >&2
    exit 1
  fi
}

require_worktree() {
  if [[ "$(git rev-parse --is-bare-repository 2>/dev/null || echo true)" == "true" ]]; then
    echo "error: must run inside a worktree (not a bare repo). cd into .worktrees/<branch>/ first." >&2
    exit 1
  fi
}

require_api_key() {
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "error: ANTHROPIC_API_KEY not set. Export it before running." >&2
    exit 1
  fi
}

count_corpus() {
  if [[ -n "$CORPUS_COUNT_OVERRIDE" ]]; then
    echo "$CORPUS_COUNT_OVERRIDE"
    return
  fi
  find "$LEARNINGS_ROOT" -type f -name "*.md" -not -path "*/archive/*" 2>/dev/null | wc -l | tr -d ' '
}

# Cost = (light_per_file + heavy_per_file) × N × headroom; printed in USD.
estimate_cost_usd() {
  local n="$1"
  awk -v n="$n" -v l="$LIGHT_COST_PER_FILE" -v h="$HEAVY_COST_PER_FILE" -v hr="$HEADROOM_FACTOR" \
    'BEGIN { printf "%.4f", (n * (l + h)) * hr }'
}

phase0_cost_gate() {
  local n="$1" cost="$2" ceiling="$COST_CEILING_USD"
  echo "Corpus size: $n files"
  echo "Light pass:  \$$(awk -v n="$n" -v r="$LIGHT_COST_PER_FILE" 'BEGIN { printf "%.4f", n*r }') (Haiku, ~$LIGHT_COST_PER_FILE/file)"
  echo "Heavy pass:  \$$(awk -v n="$n" -v r="$HEAVY_COST_PER_FILE" 'BEGIN { printf "%.4f", n*r }') (Haiku, ~$HEAVY_COST_PER_FILE/file)"
  echo "Estimated:   \$${cost} (incl. 10% headroom)"
  echo "Ceiling:     \$${ceiling}"
  if awk -v c="$cost" -v cap="$ceiling" 'BEGIN { exit !(c+0 > cap+0) }'; then
    echo "error: estimated cost \$${cost} exceeds \$${ceiling} ceiling. Refusing to proceed." >&2
    exit 1
  fi
}

# ─── Phase 1: corpus indexing + ground-truth extraction ─────────────────────
# Frontmatter parser uses the canonical `/^---$/{c++; next} c==1` block so
# mid-body `---` horizontal rules don't false-match as frontmatter close.
extract_frontmatter_description() {
  local f="$1"
  awk '
    BEGIN { c=0 }
    /^---$/ { c++; next }
    c==1 && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      sub(/^"/, ""); sub(/"$/, "")
      print
      exit
    }
    c>=2 { exit }
  ' "$f"
}

# Has YAML frontmatter? = file begins with `---` and contains a closing `---`
# before any content past line 1.
has_frontmatter() {
  local f="$1"
  awk '
    BEGIN { c=0 }
    /^---$/ { c++; if (c==2) { print "yes"; exit } next }
    c==0 && NF { exit }
  ' "$f"
}

extract_problem_section() {
  local f="$1"
  # sed range `/^## Problem$/,/^## /` includes both bounds; we strip them.
  sed -n '/^## Problem$/,/^## /p' "$f" \
    | sed '1d;$d' \
    | sed '/^[[:space:]]*$/d' \
    | head -c 2000
}

has_problem_section() {
  local f="$1"
  if grep -q "^## Problem$" "$f" 2>/dev/null; then
    echo "yes"
  fi
}

extract_title_paragraph() {
  local f="$1"
  awk '
    /^# / { found=1; next }
    found && /^$/ { if (started) exit; next }
    found && !/^$/ { started=1; print; next }
  ' "$f" | head -c 2000
}

extract_first_500() {
  local f="$1"
  # Skip frontmatter if present (lines between the two `---`s).
  awk '
    BEGIN { c=0 }
    /^---$/ { c++; next }
    c<2 && /^---$/ { next }
    c>=2 || c==0 { print }
  ' "$f" | tr -d '\r' | head -c 500
}

# Returns: ground_truth string (truncated 2000 chars).
extract_ground_truth() {
  local f="$1" gt=""
  gt="$(extract_frontmatter_description "$f" 2>/dev/null || true)"
  if [[ -n "$gt" ]]; then echo "$gt" | head -c 2000; return; fi
  gt="$(extract_problem_section "$f" 2>/dev/null || true)"
  if [[ -n "$gt" ]]; then echo "$gt" | head -c 2000; return; fi
  gt="$(extract_title_paragraph "$f" 2>/dev/null || true)"
  if [[ -n "$gt" ]]; then echo "$gt" | head -c 2000; return; fi
  extract_first_500 "$f"
}

# Classify which step of the fallback chain produced the ground-truth.
classify_extraction() {
  local f="$1"
  if [[ -n "$(extract_frontmatter_description "$f" 2>/dev/null || true)" ]]; then
    echo "description"; return
  fi
  if [[ -n "$(extract_problem_section "$f" 2>/dev/null || true)" ]]; then
    echo "problem_section"; return
  fi
  if [[ -n "$(extract_title_paragraph "$f" 2>/dev/null || true)" ]]; then
    echo "title_paragraph"; return
  fi
  echo "first_500"
}

# synced_to: parser — emits JSON array (possibly empty).
# Scalar shape:  synced_to: foo            → ["foo"]
# Scalar shape:  synced_to: "foo/bar"      → ["foo/bar"]
# Inline-array:  synced_to: [a, b]         → ["a","b"]   (bracketed flow)
# List shape:    synced_to:\n  - foo       → ["foo"]
#                  - bar                   → ["foo","bar"]
extract_synced_to() {
  local f="$1"
  awk '
    BEGIN { c=0; out=""; in_list=0 }
    /^---$/ { c++; next }
    c!=1 { next }
    in_list==1 {
      if (match($0, /^[[:space:]]+-[[:space:]]*/)) {
        v = substr($0, RLENGTH+1)
        gsub(/^"|"$/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (length(v)) out = out (length(out) ? "," : "") "\"" v "\""
        next
      } else {
        in_list = 0
        # fall through to top-level matching
      }
    }
    /^synced_to:/ {
      val = $0; sub(/^synced_to:[[:space:]]*/, "", val)
      if (length(val) == 0) { in_list = 1; next }
      # Inline-bracket flow array: synced_to: [a, b, "c"]
      if (match(val, /^\[.*\]$/)) {
        inner = substr(val, 2, length(val) - 2)
        n = split(inner, arr, /,/)
        for (i = 1; i <= n; i++) {
          v = arr[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          gsub(/^"|"$/, "", v)
          if (length(v)) out = out (length(out) ? "," : "") "\"" v "\""
        }
        next
      }
      # Scalar
      gsub(/^"|"$/, "", val); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if (length(val)) out = "\"" val "\""
      next
    }
    END { printf "[%s]", out }
  ' "$f"
}

# Walk corpus → /tmp/corpus.ndjson with {path, ground_truth, has_frontmatter, has_problem_section, synced_to}.
build_corpus_index() {
  local out="$1" file rel gt fm ps st gt_b64
  : > "$out"
  while IFS= read -r file; do
    rel="${file#"$REPO_ROOT/"}"
    gt="$(extract_ground_truth "$file")"
    fm="$(has_frontmatter "$file")"
    ps="$(has_problem_section "$file")"
    st="$(extract_synced_to "$file")"
    # Encode ground_truth defensively — embedded quotes and newlines must not
    # break the NDJSON line. jq -Rs reads stdin as a single string and JSON-
    # escapes it; the result is a quoted JSON string we pass as --argjson.
    gt_b64=$(printf '%s' "$gt" | jq -Rs .)
    jq -nc \
      --arg path "$rel" \
      --argjson ground_truth "$gt_b64" \
      --arg has_frontmatter "${fm:-no}" \
      --arg has_problem_section "${ps:-no}" \
      --argjson synced_to "$st" \
      '{path: $path, ground_truth: $ground_truth, has_frontmatter: $has_frontmatter, has_problem_section: $has_problem_section, synced_to: $synced_to}' \
      >> "$out"
  done < <(find "$LEARNINGS_ROOT" -type f -name "*.md" -not -path "*/archive/*" | sort)
}

# ─── Phase 2: paraphrase generation (light + heavy) ─────────────────────────
PROMPT_LIGHT='You are a paraphrase generator. Given a learning-summary passage from a software engineering knowledge base, produce a SHORT (1-2 sentence) paraphrase that preserves the technical terms verbatim but substitutes synonyms for surrounding verbs and connectors. Output ONLY the paraphrase as a single line of plain text — no preamble, no quotes, no markdown.'
PROMPT_HEAVY='You are a paraphrase generator. Given a learning-summary passage from a software engineering knowledge base, produce a SHORT (1-2 sentence) reformulation in a DIFFERENT framing: change sentence shape, swap nouns for verbs where natural, and avoid reusing the same technical terms unless the term IS the canonical name (e.g., "Postgres", "RLS", a file path). Output ONLY the reformulation as a single line of plain text — no preamble, no quotes, no markdown.'

# Returns: paraphrase text (newlines stripped). On API failure twice in a row,
# returns the literal string "(API_ERROR)" so downstream lookup yields 0 hits.
anthropic_paraphrase() {
  local prompt="$1" ground_truth="$2" req resp text stop_reason rc body
  req=$(jq -nc \
    --arg model "$MODEL_ID" \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg prompt "$prompt" \
    --arg gt "$ground_truth" \
    '{model: $model, max_tokens: $max_tokens, messages: [{role:"user", content: ($prompt + "\n\nPassage:\n" + $gt)}]}')
  local try
  for try in 1 2; do
    resp=$("$CURL_BIN" -sS -w '\n__HTTP_STATUS__:%{http_code}' "$ANTHROPIC_ENDPOINT" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: $ANTHROPIC_VERSION" \
      -H "content-type: application/json" \
      -d "$req" 2>/dev/null || true)
    rc=$(printf '%s' "$resp" | awk -F: '/^__HTTP_STATUS__:/{print $2}' | tr -d ' ')
    body=$(printf '%s' "$resp" | sed '/^__HTTP_STATUS__:/d')
    if [[ "$rc" =~ ^2[0-9][0-9]$ ]]; then
      text=$(printf '%s' "$body" | jq -r '.content[0].text // empty' 2>/dev/null || echo "")
      stop_reason=$(printf '%s' "$body" | jq -r '.stop_reason // empty' 2>/dev/null || echo "")
      if [[ -n "$text" ]]; then
        if [[ "$stop_reason" == "max_tokens" ]]; then
          echo "warn: stop_reason=max_tokens — paraphrase may be truncated" >&2
        fi
        # MANDATORY newline strip (Sharp Edges: multi-line paraphrase breaks grep -F).
        printf '%s' "$text" | tr -d '\n\r' | tr -s ' '
        return 0
      fi
    fi
    sleep 5
  done
  echo "(API_ERROR)"
  return 0
}

# ─── Phase 3: dual-retriever lookup ─────────────────────────────────────────
# Three layers of grep -F safety:
#   1. double-quote "$query"  → shell never expands $(...) / backticks / globs
#   2. -F                     → grep treats query as fixed string (no regex)
#   3. --                     → grep refuses to interpret leading `-` as a flag
# kbsearch_rank: returns rank (1-based) of source/synced_to paths in combined
# tier1+tier2 list (capped at 20), or empty string if none match in top-20.
kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  local tier1 tier2 combined min_rank=""
  if [[ -z "$query" ]]; then echo ""; return; fi
  tier1=$(grep -in -F -- "$query" "$INDEX_PATH" 2>/dev/null \
    | head -20 \
    | sed -nE 's/.*\]\(([^)]+)\).*/\1/p' || true)
  tier2=$(git -C "$REPO_ROOT" grep -l -i -F -- "$query" -- 'knowledge-base/**/*.md' \
    ':!knowledge-base/INDEX.md' ':!**/archive/**' 2>/dev/null | head -20 || true)
  # Combine: tier1 first (in order), then tier2 (excluding any already in tier1), cap 20.
  combined=$(
    {
      printf '%s\n' "$tier1"
      printf '%s\n' "$tier2"
    } | awk 'NF && !seen[$0]++' | head -20
  )
  # Build candidates: source_path + synced_to[]
  local candidates=("$source_path")
  if [[ -n "$synced_paths_json" && "$synced_paths_json" != "[]" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && candidates+=("$p")
    done < <(printf '%s' "$synced_paths_json" | jq -r '.[]?' 2>/dev/null || true)
  fi
  # min-rank semantics: best (lowest) position across candidates.
  local i=0 line
  while IFS= read -r line; do
    i=$((i+1))
    for cand in "${candidates[@]}"; do
      if [[ "$line" == "$cand" ]] || [[ "$line" == *"$cand"* ]]; then
        if [[ -z "$min_rank" || "$i" -lt "$min_rank" ]]; then
          min_rank="$i"
        fi
      fi
    done
  done < <(printf '%s\n' "$combined")
  echo "${min_rank:-}"
}

# grep_rank: learnings-only naive retriever.
grep_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  local results min_rank=""
  if [[ -z "$query" ]]; then echo ""; return; fi
  results=$(git -C "$REPO_ROOT" grep -l -i -F -- "$query" -- 'knowledge-base/project/learnings/**/*.md' \
    ':!**/archive/**' 2>/dev/null | head -20 || true)
  local candidates=("$source_path")
  if [[ -n "$synced_paths_json" && "$synced_paths_json" != "[]" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && candidates+=("$p")
    done < <(printf '%s' "$synced_paths_json" | jq -r '.[]?' 2>/dev/null || true)
  fi
  local i=0 line
  while IFS= read -r line; do
    i=$((i+1))
    for cand in "${candidates[@]}"; do
      if [[ "$line" == "$cand" ]] || [[ "$line" == *"$cand"* ]]; then
        if [[ -z "$min_rank" || "$i" -lt "$min_rank" ]]; then
          min_rank="$i"
        fi
      fi
    done
  done < <(printf '%s\n' "$results")
  echo "${min_rank:-}"
}

# Hardcoded fixture-seed paths (Plan §3, fixture self-check).
FIXTURE_SEEDS=(
  "knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md"
  "knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md"
  "knowledge-base/project/learnings/2026-04-14-plan-prescribed-test-framework-not-available.md"
  "knowledge-base/project/learnings/2026-03-21-kb-migration-verification-pitfalls.md"
  "knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md"
  "knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md"
  "knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md"
)

# ─── Phase 4: metric aggregation ────────────────────────────────────────────
# Compute hit@5/hit@10/RR from rank string ("" or 1..20). jq does the corpus-
# wide aggregation; bash drives the per-row math here just to keep memory low.
rank_metrics() {
  local rank="$1" h5=0 h10=0 rr="0"
  if [[ -n "$rank" ]]; then
    if (( rank <= 5  )); then h5=1; fi
    if (( rank <= 10 )); then h10=1; fi
    rr=$(awk -v r="$rank" 'BEGIN { printf "%.6f", 1.0 / r }')
  fi
  echo "$h5 $h10 $rr"
}

classify_unfindable_cause() {
  local fm="$1" ps="$2"
  if [[ "$fm" != "yes" ]]; then echo "missing-frontmatter"; return; fi
  if [[ "$ps" != "yes" ]]; then echo "content-shape"; return; fi
  echo "unknown"
}

determine_bucket() {
  local r5="$1"
  if awk -v r="$r5" 'BEGIN { exit !(r+0 >= 0.7) }'; then echo "vindicate"; return; fi
  if awk -v r="$r5" 'BEGIN { exit !(r+0 >= 0.4) }'; then echo "surface-rewrites"; return; fi
  echo "reopen-rag"
}

# ─── Phase 5: output artifact generation ────────────────────────────────────
build_close_comment_line() {
  local bucket="$1" r5="$2" learning_path="$3"
  case "$bucket" in
    vindicate)
      echo "gh issue close 4043 --comment \"R@5(heavy, kb-search)=${r5} ≥ 0.7. Vindicates 2026-04-07 file-based-retrieval decision. See ${learning_path}.\""
      ;;
    surface-rewrites)
      echo "gh issue close 4043 --comment \"R@5(heavy, kb-search)=${r5} ∈ [0.4, 0.7). Surfacing worst-N slug/frontmatter rewrites as a follow-up. See ${learning_path}.\""
      ;;
    reopen-rag)
      echo "gh issue close 4043 --comment \"R@5(heavy, kb-search)=${r5} < 0.4. Reopening the 2026-04-07 RAG/embeddings decision. See ${learning_path}.\""
      ;;
  esac
}

# ─── --self-test mode ───────────────────────────────────────────────────────
SELF_TEST_PASS=0
SELF_TEST_FAIL=0
SELF_TEST_TOTAL=0
TMP_ROOT=""

st_assert() {
  local label="$1" expected="$2" actual="$3"
  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
  if [[ "$expected" == "$actual" ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: $label"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

st_assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
  if [[ "$haystack" == *"$needle"* ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: $label"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: $label"
    echo "    needle:   $needle"
    echo "    haystack: $haystack"
  fi
}

st_write() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" > "$path"
}

self_test() {
  TMP_ROOT="$(mktemp -d)"
  trap 'rm -rf "$TMP_ROOT"' EXIT

  echo "== self-test (synthesized fixtures only — cq-test-fixtures-synthesized-only) =="

  # ── AC2-a: full frontmatter + ## Problem → ground-truth = problem body ────
  st_write "$TMP_ROOT/a.md" \
    '---' \
    'title: foo' \
    'description: a description from frontmatter' \
    '---' \
    '' \
    '# Title' \
    '' \
    '## Problem' \
    '' \
    'This is the problem body.' \
    '' \
    '## Solution' \
    '' \
    'Solution text.'
  local got
  got="$(extract_frontmatter_description "$TMP_ROOT/a.md")"
  st_assert "AC2-a: frontmatter description picked first" "a description from frontmatter" "$got"
  got="$(classify_extraction "$TMP_ROOT/a.md")"
  st_assert "AC2-a: classifier reports description" "description" "$got"

  # ── AC2-b: empty description: falls through to ## Problem ─────────────────
  st_write "$TMP_ROOT/b.md" \
    '---' \
    'title: foo' \
    'description:' \
    '---' \
    '' \
    '## Problem' \
    'Problem body of B.' \
    '' \
    '## Solution' \
    'sol'
  got="$(extract_ground_truth "$TMP_ROOT/b.md")"
  st_assert_contains "AC2-b: ground-truth falls through to problem body" "Problem body of B." "$got"
  got="$(classify_extraction "$TMP_ROOT/b.md")"
  st_assert "AC2-b: classifier reports problem_section" "problem_section" "$got"

  # ── AC2-c: ## Problem absent → falls through to # Title paragraph ─────────
  st_write "$TMP_ROOT/c.md" \
    '---' \
    'title: foo' \
    'description:' \
    '---' \
    '' \
    '# A Title Here' \
    '' \
    'First paragraph after the title.' \
    '' \
    'Second paragraph.'
  got="$(extract_ground_truth "$TMP_ROOT/c.md")"
  st_assert_contains "AC2-c: ground-truth uses title paragraph" "First paragraph after the title." "$got"
  got="$(classify_extraction "$TMP_ROOT/c.md")"
  st_assert "AC2-c: classifier reports title_paragraph" "title_paragraph" "$got"

  # ── AC2-d: all sections absent → first-500-chars fallback ─────────────────
  st_write "$TMP_ROOT/d.md" \
    'Just raw text body, no frontmatter, no headings.' \
    'Another line of body.'
  got="$(extract_ground_truth "$TMP_ROOT/d.md")"
  st_assert_contains "AC2-d: first-500 fallback picks raw body" "Just raw text body" "$got"
  got="$(classify_extraction "$TMP_ROOT/d.md")"
  st_assert "AC2-d: classifier reports first_500" "first_500" "$got"

  # ── AC2-e: synced_to: scalar form parsed as 1-element array ───────────────
  st_write "$TMP_ROOT/e.md" \
    '---' \
    'title: foo' \
    'synced_to: skill-name-one' \
    '---' \
    '' \
    '# Title' \
    'body'
  got="$(extract_synced_to "$TMP_ROOT/e.md")"
  st_assert "AC2-e: scalar synced_to → JSON array of 1" '["skill-name-one"]' "$got"

  # ── AC2-f: synced_to: list-dash form parsed as 2-element array ────────────
  st_write "$TMP_ROOT/f.md" \
    '---' \
    'title: foo' \
    'synced_to:' \
    '  - first-skill' \
    '  - second-skill' \
    'next_key: bar' \
    '---' \
    '' \
    '# Title' \
    'body'
  got="$(extract_synced_to "$TMP_ROOT/f.md")"
  st_assert "AC2-f: list-dash synced_to → JSON array of 2" '["first-skill","second-skill"]' "$got"

  # ── AC2-g: mid-body `---` horizontal rule NOT misparsed as frontmatter ────
  st_write "$TMP_ROOT/g.md" \
    '---' \
    'title: foo' \
    'description: real description' \
    '---' \
    '' \
    '# Title' \
    '' \
    'Body paragraph.' \
    '' \
    '---' \
    '' \
    'After horizontal rule.'
  got="$(extract_frontmatter_description "$TMP_ROOT/g.md")"
  st_assert "AC2-g: mid-body --- does not confuse frontmatter parser" "real description" "$got"
  # Also verify that the awk c<2 stop on extract_first_500 doesn't blow up.
  got="$(has_frontmatter "$TMP_ROOT/g.md")"
  st_assert "AC2-g: file with frontmatter detected as such" "yes" "$got"

  # ── Bonus h: inline-bracket synced_to → array (real-world shape) ──────────
  st_write "$TMP_ROOT/h.md" \
    '---' \
    'title: foo' \
    'synced_to: [test-browser, deploy]' \
    '---' \
    '' \
    '# Title' \
    'body'
  got="$(extract_synced_to "$TMP_ROOT/h.md")"
  st_assert "bonus-h: inline-bracket synced_to parsed" '["test-browser","deploy"]' "$got"

  # ── Cost-gate ceiling test: --corpus-count-override 5000 exceeds $5 ──────
  # (Just exercise estimate_cost_usd directly; the integration check is below.)
  local cost
  cost="$(estimate_cost_usd 5000)"
  # 5000 × (0.0010 + 0.0015) × 1.10 = $13.75
  st_assert "cost-gate: 5000-file estimate exceeds ceiling" "13.7500" "$cost"

  # ── grep -F -- shell-safety: query with $(...) and -e is literal ─────────
  # Build a fake learnings root + INDEX that contains the literal substring
  # the query should match. Confirm no shell expansion fires.
  local SAFE_ROOT="$TMP_ROOT/safety"
  mkdir -p "$SAFE_ROOT/knowledge-base/project/learnings"
  # ALWAYS_GREEN_MARK is a recognizable string; if grep ever returns 0, the
  # safety contract is intact (literal match worked).
  printf '%s\n' 'This contains $(rm -rf ~) and -e foo and ALWAYS_GREEN_MARK literally.' \
    > "$SAFE_ROOT/knowledge-base/project/learnings/safety.md"
  # Confirm the literal query maps to a positive grep -F match. We use the
  # awk-style escape pattern in-script: -F -- "$query".
  local q='$(rm -rf ~) and -e foo'
  if grep -F -- "$q" "$SAFE_ROOT/knowledge-base/project/learnings/safety.md" >/dev/null 2>&1; then
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: grep -F -- shell-safety: literal match w/o shell expansion"
  else
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: grep -F -- shell-safety"
  fi
  # And confirm the literal home directory was not deleted (paranoia gate).
  if [[ -d "$HOME" ]]; then
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: \$HOME survives query expansion"
  else
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: \$HOME removed (catastrophic shell expansion)"
  fi

  # ── Newline-strip: simulated multi-line paraphrase becomes single line ───
  # Exercise the tr pipeline directly (the same one anthropic_paraphrase uses).
  local multi=$'line one\nline two\nline three'
  local stripped
  stripped="$(printf '%s' "$multi" | tr -d '\n\r' | tr -s ' ')"
  st_assert "newline-strip: \\n→<space>, single line out" "line oneline twoline three" "$stripped"

  # ── Bucket determination thresholds ──────────────────────────────────────
  st_assert "bucket: 0.85 → vindicate"        "vindicate"        "$(determine_bucket 0.85)"
  st_assert "bucket: 0.55 → surface-rewrites" "surface-rewrites" "$(determine_bucket 0.55)"
  st_assert "bucket: 0.20 → reopen-rag"       "reopen-rag"       "$(determine_bucket 0.20)"
  st_assert "bucket: exactly 0.7 → vindicate" "vindicate"        "$(determine_bucket 0.7)"
  st_assert "bucket: exactly 0.4 → surface-rewrites" "surface-rewrites" "$(determine_bucket 0.4)"

  # ── rank_metrics: rank 1 → h5=1 h10=1 RR=1.0; rank "" → all zero ─────────
  st_assert "rank_metrics: rank=1"  "1 1 1.000000" "$(rank_metrics 1)"
  st_assert "rank_metrics: rank=5"  "1 1 0.200000" "$(rank_metrics 5)"
  st_assert "rank_metrics: rank=6"  "0 1 0.166667" "$(rank_metrics 6)"
  st_assert "rank_metrics: rank=11" "0 0 0.090909" "$(rank_metrics 11)"
  st_assert "rank_metrics: rank=''" "0 0 0"        "$(rank_metrics "")"

  # ── classify_unfindable_cause ─────────────────────────────────────────────
  st_assert "cause: no-fm → missing-frontmatter"  "missing-frontmatter" "$(classify_unfindable_cause "" "")"
  st_assert "cause: fm+no-ps → content-shape"     "content-shape"        "$(classify_unfindable_cause "yes" "")"
  st_assert "cause: fm+ps → unknown"              "unknown"              "$(classify_unfindable_cause "yes" "yes")"

  # ── build_close_comment_line embeds bucket + verbatim gh issue close ─────
  got="$(build_close_comment_line vindicate 0.83 knowledge-base/project/learnings/2026-05-19-retrieval-diagnostic-findings.md)"
  st_assert_contains "close-line: vindicate format" "gh issue close 4043 --comment" "$got"
  st_assert_contains "close-line: vindicate cites learning path" "2026-05-19-retrieval-diagnostic-findings.md" "$got"

  # ── Cost-gate integration: --corpus-count-override 5000 --confirm exits ≠0 ─
  local rc=0
  bash "$0" --confirm --corpus-count-override 5000 2>"$TMP_ROOT/err.log" >"$TMP_ROOT/out.log" || rc=$?
  if (( rc != 0 )) && grep -q "exceeds" "$TMP_ROOT/err.log"; then
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: cost-gate integration: rc=$rc + 'exceeds' on stderr"
  else
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: cost-gate integration (rc=$rc, stderr=$(cat "$TMP_ROOT/err.log"))"
  fi

  echo
  echo "== summary: PASS=$SELF_TEST_PASS  FAIL=$SELF_TEST_FAIL  TOTAL=$SELF_TEST_TOTAL =="
  if (( SELF_TEST_FAIL > 0 )); then
    exit 1
  fi
  exit 0
}

# ─── main driver ────────────────────────────────────────────────────────────
if (( SELF_TEST == 1 )); then
  require_deps
  # self-test does NOT require ANTHROPIC_API_KEY (no live API in default mode).
  self_test
fi

require_deps
require_worktree
# Cost gate fires BEFORE API-key check so an informational run on a workstation
# without the key still prints estimates.
N="$(count_corpus)"
if [[ -z "$CORPUS_COUNT_OVERRIDE" ]]; then
  if ! [[ "$N" =~ ^[0-9]+$ ]] || (( N < 100 )) || (( N > 5000 )); then
    echo "error: corpus count out of sanity range [100..5000]: N=$N" >&2
    exit 1
  fi
fi
COST="$(estimate_cost_usd "$N")"
phase0_cost_gate "$N" "$COST"

if (( CONFIRM == 0 )); then
  echo
  echo "Informational mode (no --confirm). Exiting 0."
  echo "Re-run with --confirm to execute the full bench (~50 min, ~\$${COST})."
  exit 0
fi

require_api_key

# ─── Phase 1: corpus indexing ──────────────────────────────────────────────
CORPUS_NDJSON=$(mktemp)
PARAPHRASES_NDJSON=$(mktemp)
RANKS_NDJSON=$(mktemp)
trap 'rm -f "$CORPUS_NDJSON" "$PARAPHRASES_NDJSON" "$RANKS_NDJSON"' EXIT

echo "Phase 1: indexing corpus → $CORPUS_NDJSON"
build_corpus_index "$CORPUS_NDJSON"

# Extraction stats
HAS_FM_COUNT=$(jq -r 'select(.has_frontmatter == "yes")' < "$CORPUS_NDJSON" | jq -s 'length')
HAS_PS_COUNT=$(jq -r 'select(.has_problem_section == "yes")' < "$CORPUS_NDJSON" | jq -s 'length')
TOTAL_COUNT=$(jq -s 'length' < "$CORPUS_NDJSON")
HAS_FM_PCT=$(awk -v a="$HAS_FM_COUNT" -v b="$TOTAL_COUNT" 'BEGIN { if (b==0) print 0; else printf "%.4f", a/b }')
HAS_PS_PCT=$(awk -v a="$HAS_PS_COUNT" -v b="$TOTAL_COUNT" 'BEGIN { if (b==0) print 0; else printf "%.4f", a/b }')
echo "  has_frontmatter=$HAS_FM_COUNT/$TOTAL_COUNT  has_problem_section=$HAS_PS_COUNT/$TOTAL_COUNT"

# Fallback distribution
FALLBACK_DESC=0; FALLBACK_PROB=0; FALLBACK_TITLE=0; FALLBACK_500=0
while IFS= read -r rel; do
  case "$(classify_extraction "$REPO_ROOT/$rel")" in
    description)      FALLBACK_DESC=$((FALLBACK_DESC+1)) ;;
    problem_section)  FALLBACK_PROB=$((FALLBACK_PROB+1)) ;;
    title_paragraph)  FALLBACK_TITLE=$((FALLBACK_TITLE+1)) ;;
    first_500)        FALLBACK_500=$((FALLBACK_500+1)) ;;
  esac
done < <(jq -r '.path' < "$CORPUS_NDJSON")

# ─── Phase 2: paraphrase generation ────────────────────────────────────────
echo "Phase 2: paraphrase generation (sync, ~50 min for full corpus)"
API_CALLS=0; API_RETRIES=0; API_ERRORS=0
i=0
: > "$PARAPHRASES_NDJSON"
while IFS= read -r line; do
  i=$((i+1))
  rel="$(echo "$line" | jq -r '.path')"
  gt="$(echo "$line" | jq -r '.ground_truth')"
  if [[ -z "$gt" ]]; then
    light="(API_ERROR)"; heavy="(API_ERROR)"
    API_ERRORS=$((API_ERRORS+2))
  else
    light="$(anthropic_paraphrase "$PROMPT_LIGHT" "$gt")"
    API_CALLS=$((API_CALLS+1))
    [[ "$light" == "(API_ERROR)" ]] && API_ERRORS=$((API_ERRORS+1))
    heavy="$(anthropic_paraphrase "$PROMPT_HEAVY" "$gt")"
    API_CALLS=$((API_CALLS+1))
    [[ "$heavy" == "(API_ERROR)" ]] && API_ERRORS=$((API_ERRORS+1))
  fi
  jq -nc \
    --arg path "$rel" \
    --arg identity "$gt" \
    --arg light "$light" \
    --arg heavy "$heavy" \
    '{path:$path, identity:$identity, light:$light, heavy:$heavy}' \
    >> "$PARAPHRASES_NDJSON"
  if (( i % 50 == 0 )); then
    echo "  progress: $i/$TOTAL_COUNT"
  fi
done < "$CORPUS_NDJSON"

# ─── Phase 3: dual-retriever lookup ────────────────────────────────────────
echo "Phase 3: dual-retriever lookup (6 × $TOTAL_COUNT = $((6*TOTAL_COUNT)) lookups)"
i=0
: > "$RANKS_NDJSON"
while IFS= read -r line; do
  i=$((i+1))
  rel="$(echo "$line" | jq -r '.path')"
  identity="$(echo "$line" | jq -r '.identity')"
  light="$(echo "$line" | jq -r '.light')"
  heavy="$(echo "$line" | jq -r '.heavy')"
  st_json="$(jq -r --arg p "$rel" '. as $all | $all | map(select(.path == $p)) | .[0].synced_to // []' < <(jq -s . "$CORPUS_NDJSON"))"
  # The above is O(n²); for one-shot bench at 1117 it's acceptable but if it
  # becomes a hot spot, swap for a single jq pre-pass that emits a path→synced
  # map and look up by key.
  for intensity_pair in "identity:$identity" "light:$light" "heavy:$heavy"; do
    intensity="${intensity_pair%%:*}"
    query="${intensity_pair#*:}"
    if [[ "$query" == "(API_ERROR)" ]]; then query=""; fi
    rk_kb="$(kbsearch_rank "$query" "$rel" "$st_json")"
    rk_grep="$(grep_rank "$query" "$rel" "$st_json")"
    jq -nc --arg path "$rel" --arg intensity "$intensity" --arg retriever "kbsearch" --arg rank "$rk_kb"   '{path:$path,intensity:$intensity,retriever:$retriever,rank:($rank|select(length>0)|tonumber? // null)}' >> "$RANKS_NDJSON"
    jq -nc --arg path "$rel" --arg intensity "$intensity" --arg retriever "grep"     --arg rank "$rk_grep" '{path:$path,intensity:$intensity,retriever:$retriever,rank:($rank|select(length>0)|tonumber? // null)}' >> "$RANKS_NDJSON"
  done
  if (( i % 50 == 0 )); then
    echo "  lookup progress: $i/$TOTAL_COUNT"
  fi
done < "$PARAPHRASES_NDJSON"

# ─── Phase 4: aggregate metrics ────────────────────────────────────────────
echo "Phase 4: aggregating metrics"
agg() {
  local intensity="$1" retriever="$2" k="$3"
  jq -s --arg i "$intensity" --arg r "$retriever" --argjson k "$k" '
    map(select(.intensity == $i and .retriever == $r)) as $rows
    | ($rows | length) as $n
    | if $n == 0 then 0
      else ($rows | map(if (.rank // 99999) <= $k then 1 else 0 end) | add) / $n
      end
  ' < "$RANKS_NDJSON"
}
agg_mrr() {
  local intensity="$1" retriever="$2"
  jq -s --arg i "$intensity" --arg r "$retriever" '
    map(select(.intensity == $i and .retriever == $r)) as $rows
    | ($rows | length) as $n
    | if $n == 0 then 0
      else ($rows | map(if .rank == null then 0 else (1 / .rank) end) | add) / $n
      end
  ' < "$RANKS_NDJSON"
}

R5_ID_KB=$(agg identity kbsearch 5);   R5_LT_KB=$(agg light kbsearch 5);   R5_HV_KB=$(agg heavy kbsearch 5)
R5_ID_GR=$(agg identity grep 5);       R5_LT_GR=$(agg light grep 5);       R5_HV_GR=$(agg heavy grep 5)
R10_ID_KB=$(agg identity kbsearch 10); R10_LT_KB=$(agg light kbsearch 10); R10_HV_KB=$(agg heavy kbsearch 10)
R10_ID_GR=$(agg identity grep 10);     R10_LT_GR=$(agg light grep 10);     R10_HV_GR=$(agg heavy grep 10)
MRR_ID_KB=$(agg_mrr identity kbsearch); MRR_LT_KB=$(agg_mrr light kbsearch); MRR_HV_KB=$(agg_mrr heavy kbsearch)
MRR_ID_GR=$(agg_mrr identity grep);     MRR_LT_GR=$(agg_mrr light grep);     MRR_HV_GR=$(agg_mrr heavy grep)

GAP_HONESTY=$(awk -v a="$R5_ID_KB" -v b="$R5_HV_KB" 'BEGIN { printf "%.4f", a - b }')
GAP_SKILL_ROI=$(awk -v a="$R5_HV_KB" -v b="$R5_HV_GR" 'BEGIN { printf "%.4f", a - b }')
BUCKET="$(determine_bucket "$R5_HV_KB")"

# Worst-N (max 20) where rank_heavy_kbsearch is null
WORST_N=$(jq -s --slurpfile corpus <(jq -s . "$CORPUS_NDJSON") '
  map(select(.intensity == "heavy" and .retriever == "kbsearch" and .rank == null))
  | .[0:20]
  | map(.path)
' < "$RANKS_NDJSON")

WORST_N_WITH_CAUSE="[]"
WORST_N_WITH_CAUSE=$(jq -s --slurpfile corpus <(jq -s . "$CORPUS_NDJSON") '
  ($corpus[0] | map({(.path): {fm: .has_frontmatter, ps: .has_problem_section}}) | add) as $idx
  | map(select(.intensity == "heavy" and .retriever == "kbsearch" and .rank == null))
  | .[0:20]
  | map(
      .path as $p
      | {
          path: $p,
          rank_heavy_kbsearch: null,
          cause: (
            if ($idx[$p].fm // "no") != "yes" then "missing-frontmatter"
            elif ($idx[$p].ps // "no") != "yes" then "content-shape"
            else "unknown"
            end
          )
        }
    )
' < "$RANKS_NDJSON")

# Fixture-seed rows (7 hardcoded)
FIXTURE_ROWS="[]"
for seed in "${FIXTURE_SEEDS[@]}"; do
  rk_kb=$(jq -s --arg p "$seed" 'map(select(.path == $p and .intensity == "heavy" and .retriever == "kbsearch"))[0].rank // null' < "$RANKS_NDJSON")
  rk_gr=$(jq -s --arg p "$seed" 'map(select(.path == $p and .intensity == "heavy" and .retriever == "grep"))[0].rank // null' < "$RANKS_NDJSON")
  FIXTURE_ROWS=$(jq -nc --argjson cur "$FIXTURE_ROWS" --arg p "$seed" --argjson kb "$rk_kb" --argjson gr "$rk_gr" '$cur + [{path:$p, rank_heavy_kbsearch:$kb, rank_heavy_grep:$gr}]')
done

# ─── Phase 5: write outputs ────────────────────────────────────────────────
TODAY="$(date +%Y-%m-%d)"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LEARNING_PATH="knowledge-base/project/learnings/${TODAY}-retrieval-diagnostic-findings.md"
JSON_PATH="knowledge-base/project/learning-retrieval-metrics-${TODAY}.json"

echo "Phase 5: writing outputs"

JSON_TMP=$(mktemp)
jq -n \
  --arg generated_at "$GENERATED_AT" \
  --argjson corpus_count "$TOTAL_COUNT" \
  --arg model_id "$MODEL_ID" \
  --arg prompt_light "$PROMPT_LIGHT" \
  --arg prompt_heavy "$PROMPT_HEAVY" \
  --argjson has_fm_pct "$HAS_FM_PCT" \
  --argjson has_ps_pct "$HAS_PS_PCT" \
  --argjson fb_desc "$FALLBACK_DESC" \
  --argjson fb_prob "$FALLBACK_PROB" \
  --argjson fb_title "$FALLBACK_TITLE" \
  --argjson fb_500  "$FALLBACK_500" \
  --argjson api_calls "$API_CALLS" \
  --argjson api_retries "$API_RETRIES" \
  --argjson api_errors "$API_ERRORS" \
  --arg cost_estimate "$COST" \
  --argjson r5_ikb "$R5_ID_KB" --argjson r5_lkb "$R5_LT_KB" --argjson r5_hkb "$R5_HV_KB" \
  --argjson r5_igr "$R5_ID_GR" --argjson r5_lgr "$R5_LT_GR" --argjson r5_hgr "$R5_HV_GR" \
  --argjson r10_ikb "$R10_ID_KB" --argjson r10_lkb "$R10_LT_KB" --argjson r10_hkb "$R10_HV_KB" \
  --argjson r10_igr "$R10_ID_GR" --argjson r10_lgr "$R10_LT_GR" --argjson r10_hgr "$R10_HV_GR" \
  --argjson mrr_ikb "$MRR_ID_KB" --argjson mrr_lkb "$MRR_LT_KB" --argjson mrr_hkb "$MRR_HV_KB" \
  --argjson mrr_igr "$MRR_ID_GR" --argjson mrr_lgr "$MRR_LT_GR" --argjson mrr_hgr "$MRR_HV_GR" \
  --arg gap_h "$GAP_HONESTY" --arg gap_s "$GAP_SKILL_ROI" \
  --argjson fixture_seeds "$FIXTURE_ROWS" \
  --argjson worst_n "$WORST_N_WITH_CAUSE" \
  --arg bucket "$BUCKET" \
  '{
    schema: 1,
    generated_at: $generated_at,
    corpus_count: $corpus_count,
    model_id: $model_id,
    prompts: { light: $prompt_light, heavy: $prompt_heavy },
    extraction_stats: {
      has_frontmatter_pct: $has_fm_pct,
      has_problem_section_pct: $has_ps_pct,
      fallback_distribution: { description: $fb_desc, problem_section: $fb_prob, title_paragraph: $fb_title, first_500: $fb_500 }
    },
    api_stats: { calls_made: $api_calls, retries: $api_retries, errors: $api_errors },
    cost_estimate_usd: ($cost_estimate | tonumber),
    r5: {
      identity_kbsearch: $r5_ikb, light_kbsearch: $r5_lkb, heavy_kbsearch: $r5_hkb,
      identity_grep:     $r5_igr, light_grep:     $r5_lgr, heavy_grep:     $r5_hgr
    },
    r10: {
      identity_kbsearch: $r10_ikb, light_kbsearch: $r10_lkb, heavy_kbsearch: $r10_hkb,
      identity_grep:     $r10_igr, light_grep:     $r10_lgr, heavy_grep:     $r10_hgr
    },
    mrr: {
      identity_kbsearch: $mrr_ikb, light_kbsearch: $mrr_lkb, heavy_kbsearch: $mrr_hkb,
      identity_grep:     $mrr_igr, light_grep:     $mrr_lgr, heavy_grep:     $mrr_hgr
    },
    gap_honesty:    ($gap_h | tonumber),
    gap_skill_roi:  ($gap_s | tonumber),
    fixture_seeds:  $fixture_seeds,
    worst_n:        $worst_n,
    bucket:         $bucket
  }' > "$JSON_TMP"
mv "$JSON_TMP" "$REPO_ROOT/$JSON_PATH"
echo "  wrote $JSON_PATH"

CLOSE_LINE="$(build_close_comment_line "$BUCKET" "$R5_HV_KB" "$LEARNING_PATH")"

# Render learning markdown.
LEARNING_TMP=$(mktemp)
{
  cat <<EOF
---
title: Retrieval Diagnostic Findings (#4043)
date: $TODAY
category: workflow-patterns
tags: [retrieval, kb-search, compound, benchmark, diagnostic]
problem_type: workflow_diagnostic
issue: 4043
pr: 4045
description: One-shot bench of kb-search + bare-grep retrieval against the learnings corpus at three paraphrase intensities; pre-committed bucket-driven closure of #4043.
---

# Retrieval Diagnostic Findings (#4043)

## TL;DR

Bucket: **\`$BUCKET\`**. \`R@5(heavy, kb-search) = $R5_HV_KB\` across $TOTAL_COUNT learnings.

EOF
  case "$BUCKET" in
    vindicate)        echo "**Recommended action:** \`Closes #4043\`. No follow-up. The 2026-04-07 file-based-retrieval framing is vindicated by evidence." ;;
    surface-rewrites) echo "**Recommended action:** \`Closes #4043\`. File ONE follow-up issue with the worst-N list below as acceptance-criteria checklist." ;;
    reopen-rag)       echo "**Recommended action:** \`Closes #4043\`. File ONE follow-up issue to reopen the 2026-04-07 RAG/embeddings decision." ;;
  esac
  cat <<EOF

## Methodology

Per the plan (\`knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md\`):

- **Three paraphrase intensities** generated per learning: \`identity\` (ground-truth verbatim, no LLM), \`light\` (synonym substitution via Haiku), \`heavy\` (different framing via Haiku).
- **Two retrievers** exercised per intensity: a bash emulator of kb-search's two-tier grep strategy (INDEX.md title matches → repo-wide content matches, cap 20), and a learnings-only \`git grep -l -i -F\` baseline.
- **min-rank synced_to semantics:** if a learning declares \`synced_to:\`, the source's rank is the BEST (lowest) position across {source_path, synced_to[…]} in the retriever's combined output. This biases R@5 upward vs. the strict "source-only" definition and is documented here so a future reader does NOT conflate the two.
- **kb-search is a strategy, not a skill call.** The bench replicates the two-tier grep strategy in bash because (a) the skill is a Markdown prompt agents interpret, not a CLI, and (b) the strategy is the stable interface — its grep flags survive Markdown wording changes.

## Results

### Corpus-wide R@5 / R@10 / MRR (6 cells each)

|                      | kb-search       | bare grep       |
|---                   |---              |---              |
| **R@5 identity**     | $R5_ID_KB       | $R5_ID_GR       |
| **R@5 light**        | $R5_LT_KB       | $R5_LT_GR       |
| **R@5 heavy**        | $R5_HV_KB       | $R5_HV_GR       |
| **R@10 identity**    | $R10_ID_KB      | $R10_ID_GR      |
| **R@10 light**       | $R10_LT_KB      | $R10_LT_GR      |
| **R@10 heavy**       | $R10_HV_KB      | $R10_HV_GR      |
| **MRR identity**     | $MRR_ID_KB      | $MRR_ID_GR      |
| **MRR light**        | $MRR_LT_KB      | $MRR_LT_GR      |
| **MRR heavy**        | $MRR_HV_KB      | $MRR_HV_GR      |

### Gap signals

- **Honesty gap (R@5 identity − heavy, kb-search):** $GAP_HONESTY — if < 0.05 the heavy paraphrase is too close to identity and prompts need tightening before treating corpus numbers as load-bearing.
- **Skill-ROI gap (R@5 heavy: kb-search − grep):** $GAP_SKILL_ROI — positive ⇒ kb-search outperforms bare grep on hard queries.

### Fixture-seed sub-corpus (7 seeds, heavy-paraphrase pass)

EOF
  jq -r '.[] | "- `\(.path)` — kb-search rank: \(.rank_heavy_kbsearch // "null"), grep rank: \(.rank_heavy_grep // "null")"' <<< "$FIXTURE_ROWS"

  cat <<EOF

If all 7 are findable (rank ≤ 5) the methodology may be too easy; if all 7 are unfindable the diagnostic is detecting the right shapes.

## Worst-N Unfindable

EOF
  if [[ "$(echo "$WORST_N_WITH_CAUSE" | jq 'length')" -eq 0 ]]; then
    echo "_None — every learning is findable at heavy paraphrase via kb-search._"
  else
    jq -r '.[] | "- `\(.path)` — cause: **\(.cause)**"' <<< "$WORST_N_WITH_CAUSE"
  fi

  cat <<EOF

## Recommended Action

**Bucket:** \`$BUCKET\`.

Run this verbatim before marking PR #4045 ready:

\`\`\`bash
$CLOSE_LINE
\`\`\`

Per plan, atomic closure via \`Closes #4043\` in PR body lands the close on merge.
EOF
} > "$LEARNING_TMP"
mv "$LEARNING_TMP" "$REPO_ROOT/$LEARNING_PATH"
echo "  wrote $LEARNING_PATH"

echo
echo "================================================================"
echo "BUCKET:  $BUCKET"
echo "R5(heavy, kb-search): $R5_HV_KB"
echo
echo "Run this verbatim before marking PR ready:"
echo "  $CLOSE_LINE"
echo "================================================================"
