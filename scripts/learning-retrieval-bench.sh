#!/usr/bin/env bash
# learning-retrieval-bench.sh — one-shot retrieval diagnostic for knowledge-base/project/learnings/
#
# Plan:       knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md
# Spec:       knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md
# Brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md
# Precedent:  scripts/compound-promote.sh:124-200 (Anthropic curl + jq pattern, ADR-021)
#
# Schema versions for knowledge-base/project/learning-retrieval-metrics-<date>.json:
#   schema: 1 — initial (#4043).
#   schema: 2 — Stage 2 (#4176): adds top-level r5_identity / r5_light /
#               r5_heavy for the kbsearch retriever (split from the
#               combined r5 object) so ladder triage can read R@5 per
#               bucket without re-aggregating.
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
CACHE_PARAPHRASES=""
NO_PARAPHRASE="${NO_PARAPHRASE:-0}"
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
  cat <<'HELP'
learning-retrieval-bench.sh — one-shot retrieval diagnostic for knowledge-base/project/learnings/

Plan:       knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md
Spec:       knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md
Brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md
Precedent:  scripts/compound-promote.sh:124-200 (Anthropic curl + jq pattern, ADR-021)

Usage:
  bash scripts/learning-retrieval-bench.sh                       # informational; prints cost estimate + exits 0
  bash scripts/learning-retrieval-bench.sh --confirm             # full run (~50 min, ~$3.07)
  bash scripts/learning-retrieval-bench.sh --self-test           # inline synthesized-fixture tests

Flags:
  --confirm                       Required to actually execute the full bench (cost-gated).
  --self-test                     Run the inline self-test suite; no Anthropic calls.
  --corpus-count-override <N>     Test-only: short-circuit corpus walk to value N.
  --cache-paraphrases <path>      Write/read paraphrases NDJSON at <path>. Survives EXIT-trap rm.
                                  Cache-hit rerun (full corpus coverage in <path>) skips Phase 2
                                  entirely — no Anthropic key required and no spend.
  --no-paraphrase                 Skip Stage 2 query-paraphrase union (#4176). Equivalent to
                                  exporting NO_PARAPHRASE=1. Forces every kbsearch_rank invocation
                                  to use only the baseline two-tier grep.
  --help, -h                      This text.

Closes #4043 once committed alongside output learning + sibling JSON.

Env-var hooks (self-test fixture overrides only — cq-test-fixtures-synthesized-only):
  LEARNINGS_ROOT, INDEX_PATH, OUTPUT_DIR     redirect script reads/writes
  CURL_BIN                                   inject mock curl for API tests
  LIVE_API=1                                 opt in to live calls in self-test
HELP
}

while (( $# > 0 )); do
  case "$1" in
    --confirm)                    CONFIRM=1 ;;
    --self-test)                  SELF_TEST=1 ;;
    --corpus-count-override)      CORPUS_COUNT_OVERRIDE="$2"; shift ;;
    --cache-paraphrases)          CACHE_PARAPHRASES="$2"; shift ;;
    --no-paraphrase)              NO_PARAPHRASE=1 ;;
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
  # awk extracts everything between `## Problem` and the next `## ` heading
  # (exclusive on both bounds). Unlike `sed '/^## Problem$/,/^## /p | sed
  # 1d;$d`, this does NOT drop the section's last line when `## Problem` is
  # the file's terminal heading (no following `## ` to bound the range).
  awk '
    /^## Problem$/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && NF { print }
  ' "$f" | head -c 2000
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
# stage-2-paraphrase-union-v1 (#4176): query-side paraphrase pre-pass.
# Mirrored verbatim in plugins/soleur/skills/kb-search/SKILL.md; the
# plugins/soleur/test/kb-search-lockstep.test.sh CI assertion fails when
# the token appears in only one of the two files (TR2 lockstep contract).
PROMPT_QUERY_PARAPHRASE='You are a query paraphrase generator. Given a search query against a software engineering knowledge base, produce a SHORT (1 sentence or less) reformulation in a DIFFERENT vocabulary: swap verbs for nouns where natural, substitute domain-canonical synonyms (e.g., "saturating workers" → "connection pool exhaustion"), and keep the query terse. Output ONLY the reformulation as a single line of plain text — no preamble, no quotes, no markdown.'

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
  local _try
  for _try in 1 2; do
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
#
# **Methodology (revised post-first-run).** The original plan §Phase 3
# passed the full paraphrase sentence as the `grep -F` query. Real
# kb-search consumes a short $KEYWORD; an agent doesn't paste a paragraph.
# A sentence-paraphrase never substring-matches verbatim source text →
# the previous run produced R@5(light|heavy) ≡ 0 across the corpus
# (methodology floor, not a retrieval finding).
#
# This revision extracts keywords from each (identity|light|heavy) query
# via a bash heuristic — lowercase, tokenize on non-alphanumerics, drop
# stopwords + tokens < 4 chars, dedup, take top-K longest. Retrieval is
# now token-overlap ranking: score each candidate path by the number of
# distinct extracted tokens that substring-match the file/INDEX line.
# Applied uniformly to identity/light/heavy so the honesty gap signal
# stays apples-to-apples.
#
# Three layers of `grep -F` safety preserved (per-token now, not per-query):
#   1. double-quote "$token"  → shell never expands $(...) / backticks / globs
#   2. -F                     → grep treats token as fixed string (no regex)
#   3. --                     → grep refuses to interpret leading `-` as a flag

# Common English stopwords + bench-noise terms. Comma-separated for awk.
STOPWORDS="about,above,after,again,against,also,although,always,among,because,before,being,below,between,both,call,calls,came,case,cases,cause,caused,causes,check,checks,common,could,does,doing,done,each,either,enough,even,every,ever,first,from,gets,give,gives,goes,have,having,here,however,important,into,issue,just,keep,kind,know,less,like,liked,line,lines,long,made,make,makes,many,more,most,much,must,name,need,needs,never,next,none,only,onto,other,others,over,plus,real,return,same,seem,seems,seen,sent,show,shows,side,since,some,sort,sorts,still,such,sure,take,takes,than,that,thanks,them,then,there,these,they,this,those,thus,time,times,tool,tools,turn,turns,until,upon,used,uses,using,very,want,wants,were,what,whatever,when,where,which,while,with,within,without,work,works,would,your"

# extract_keywords: stdin/$1 text → newline-separated top-K longest non-stopword tokens (≥4 chars).
extract_keywords() {
  local text="$1" k="${2:-3}"
  if [[ -z "$text" ]]; then return; fi
  printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9_-' '\n' \
    | awk -v stop="$STOPWORDS" -v k="$k" '
        BEGIN {
          n = split(stop, arr, ","); for (i=1; i<=n; i++) S[arr[i]] = 1
        }
        # Skip empty, short, all-numeric, and stopword tokens.
        length($0) >= 4 && !($0 in S) && !match($0, /^[0-9_-]+$/) {
          if (seen[$0]++) next
          # Emit "length<TAB>token" so we can sort by length desc.
          print length($0) "\t" $0
        }
      ' \
    | sort -rn -k1,1 \
    | awk -v k="$k" '{ print $2; if (++c >= k) exit }'
}

# rank_paths_by_token_overlap: given (tokens, candidate-grep-fn), return up
# to 20 paths sorted by # of distinct tokens matched (desc). Caller passes
# the corpus-scoping git-grep invocation as the second arg via shell function.
#
# Output: one path per line, sorted by token-overlap score desc (ties broken
# by lexicographic path order).
rank_paths_by_token_overlap_corpus() {
  local tokens="$1"   # newline-separated
  local scope="$2"    # "kb-wide" or "learnings-only"
  if [[ -z "$tokens" ]]; then return; fi
  local tmp
  tmp=$(mktemp)
  local token
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    # Pathspec choice: directory prefix (no glob) covers BOTH top-level AND
    # subdir files. The original `'knowledge-base/**/*.md'` shape matched
    # only subdir files (git pathspec `**` requires intermediate dirs —
    # same gobwas trap as lefthook globs; see
    # `2026-03-21-lefthook-gobwas-glob-double-star.md`). For learnings/ at
    # this scale (~822 top-level, ~301 subdir) that meant the first bench
    # run searched only ~27% of the corpus.
    case "$scope" in
      kb-wide)
        git -C "$REPO_ROOT" grep -l -i -F -- "$token" -- 'knowledge-base/' \
          ':(exclude)knowledge-base/INDEX.md' ':(exclude,glob)**/archive/**' 2>/dev/null
        ;;
      learnings-only)
        git -C "$REPO_ROOT" grep -l -i -F -- "$token" -- 'knowledge-base/project/learnings/' \
          ':(exclude,glob)**/archive/**' 2>/dev/null
        ;;
    esac >> "$tmp"
  done <<< "$tokens"
  # Each match counts once. uniq -c gives "score path". Sort by score desc.
  sort "$tmp" | uniq -c | sort -rn -k1,1 -k2,2 | awk '{ $1=""; sub(/^ +/, ""); print }' | head -20
  rm -f "$tmp"
}

# rank_indexmd_by_token_overlap: tier-1 — score INDEX.md LINES (one per
# learning entry) by token-overlap, return their path targets (prefixed
# with `knowledge-base/` since INDEX.md uses domain-relative paths).
rank_indexmd_by_token_overlap() {
  local tokens="$1"
  if [[ -z "$tokens" ]] || [[ ! -f "$INDEX_PATH" ]]; then return; fi
  local tmp
  tmp=$(mktemp)
  local token
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    # Match lines containing this token; extract the markdown link target.
    grep -i -F -- "$token" "$INDEX_PATH" 2>/dev/null \
      | sed -nE 's/.*\]\(([^)]+)\).*/\1/p' \
      | sed 's|^|knowledge-base/|' >> "$tmp"
  done <<< "$tokens"
  sort "$tmp" | uniq -c | sort -rn -k1,1 -k2,2 | awk '{ $1=""; sub(/^ +/, ""); print }' | head -20
  rm -f "$tmp"
}

# rank_paths_min_rank: combined ranked list + candidate paths → 1-based min
# rank or "" if none of the candidates appear in top-20.
rank_paths_min_rank() {
  local combined="$1" source_path="$2" synced_paths_json="$3"
  local candidates=("$source_path")
  if [[ -n "$synced_paths_json" && "$synced_paths_json" != "[]" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && candidates+=("$p")
    done < <(printf '%s' "$synced_paths_json" | jq -r '.[]?' 2>/dev/null || true)
  fi
  local i=0 min_rank=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    i=$((i+1))
    for cand in "${candidates[@]}"; do
      if [[ "$line" == "$cand" ]]; then
        if [[ -z "$min_rank" || "$i" -lt "$min_rank" ]]; then
          min_rank="$i"
        fi
      fi
    done
  done <<< "$combined"
  echo "${min_rank:-}"
}

# Sensitive-query regex (#4176). Value-shape-anchored AND prefix-anchored —
# refuses paraphrase forward when the query carries a credential-looking
# literal: assignment-operator + base64 blob, vendor key prefixes (Anthropic,
# OpenAI, GitHub, AWS, Stripe, Slack), JWT triple-blob, postgres dsn= prefix.
# Bare topic-keyword queries like "JWT token refresh" or "keypress event" do
# NOT match — the prefix anchors and assignment shape avoid blocking
# legitimate developer vocabulary. Mirrors plugins/soleur/skills/kb-search/SKILL.md
# §Phase 2.5 guard; the kb-search-lockstep.test.sh asserts byte-equality of
# the regex literal across both files.
SENSITIVE_QUERY_REGEX='((=|:)[[:space:]]*[a-zA-Z0-9+/]{16,}|sk-(ant-)?[a-zA-Z0-9_-]{20,}|sk_live_[a-zA-Z0-9]{20,}|pk_live_[a-zA-Z0-9]{20,}|rk_live_[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|ghs_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{40,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[abprs]-[a-zA-Z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_.+/=-]{15,}|dsn=)'

# query_is_sensitive: returns 0 (match) when the query carries a credential-
# shaped literal, 1 otherwise. Case-insensitive.
query_is_sensitive() {
  local q="$1"
  printf '%s' "$q" | grep -iEq "$SENSITIVE_QUERY_REGEX"
}

# kbsearch_rank: two-tier (INDEX.md title-match + corpus content-match) with
# token-overlap scoring. Tier-1 scoped to /learnings/ paths and capped at 8;
# tier-2 scoped to learnings-only and capped at 12. Total bounded by tier
# caps (8+12); no outer head -20 needed. See #4119 brainstorm/spec/plan.
#
# Stage 2 (#4176): when the combined tier-1+tier-2 unique-path count is < 5
# AND NO_PARAPHRASE != 1 AND the query is not sensitive-value-shaped, fan
# out 3 paraphrase variants via PROMPT_QUERY_PARAPHRASE and union-rank by
# the count of paraphrase-variants that hit each path. The 4 strings
# (original + 3 variants) each run the baseline two-tier path under their
# own per-tier 8+12 caps; the per-variant ranked lists are then merged into
# a single flat hit-count rerank capped at 20 (the cap-split metadata is
# lost at merge time — per-tier identity does not survive the union, by
# design — and 20 is the absolute ceiling on what kb-search returns).
kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  if [[ -z "$query" ]]; then echo ""; return; fi
  local tokens tier1 tier2 combined
  tokens=$(extract_keywords "$query" 3)
  if [[ -z "$tokens" ]]; then echo ""; return; fi
  # Tier 1: INDEX.md hits anchored to knowledge-base/project/learnings/ so a
  # future path like `sessions/learnings-retrospective/` cannot leak through.
  tier1=$(rank_indexmd_by_token_overlap "$tokens" \
    | awk '$0 ~ "(^|/)knowledge-base/project/learnings/"' \
    | head -8)
  tier2=$(rank_paths_by_token_overlap_corpus "$tokens" learnings-only | head -12)
  combined=$({ printf '%s\n' "$tier1"; printf '%s\n' "$tier2"; } \
    | awk 'NF && !seen[$0]++')

  # stage-2-paraphrase-union-v1: adaptive paraphrase pre-pass.
  local baseline_count
  baseline_count=$(printf '%s\n' "$combined" | awk 'NF' | wc -l | tr -d ' ')
  if (( baseline_count < 5 )) \
    && [[ "${NO_PARAPHRASE:-0}" != "1" ]] \
    && [[ -n "${ANTHROPIC_API_KEY:-}" ]] \
    && ! query_is_sensitive "$query"; then
    local variants v vtokens vtier1 vtier2 vcomb merged_paths
    variants=()
    local i
    for i in 1 2 3; do
      v=$(anthropic_paraphrase "$PROMPT_QUERY_PARAPHRASE" "$query")
      if [[ -n "$v" && "$v" != "(API_ERROR)" ]]; then
        # Dedupe variants by exact-string-match.
        local seen_var=0 existing
        for existing in "${variants[@]}"; do
          [[ "$existing" == "$v" ]] && { seen_var=1; break; }
        done
        (( seen_var == 0 )) && variants+=("$v")
      fi
    done
    if (( ${#variants[@]} == 0 )); then
      echo "kb-search: WARN — paraphrase generation failed: all 3 variants returned (API_ERROR) — falling back to baseline grep" >&2
    else
      merged_paths=$(mktemp)
      # Original query's combined hits + each variant's combined hits, one
      # path per line. uniq -c gives hit-count per path; sort -rn ranks.
      printf '%s\n' "$combined" | awk 'NF' >> "$merged_paths"
      for v in "${variants[@]}"; do
        vtokens=$(extract_keywords "$v" 3)
        [[ -z "$vtokens" ]] && continue
        vtier1=$(rank_indexmd_by_token_overlap "$vtokens" \
          | awk '$0 ~ "(^|/)knowledge-base/project/learnings/"' \
          | head -8)
        vtier2=$(rank_paths_by_token_overlap_corpus "$vtokens" learnings-only | head -12)
        vcomb=$({ printf '%s\n' "$vtier1"; printf '%s\n' "$vtier2"; } \
          | awk 'NF && !seen[$0]++')
        printf '%s\n' "$vcomb" | awk 'NF' >> "$merged_paths"
      done
      # Re-rank: count hits per path across original + variants, sort by
      # hit-count desc then lexicographic. Flat cap at 20 (per-tier 8/12
      # identity is lost at merge time — see comment above kbsearch_rank;
      # union-by-hit-count is the new ranking signal).
      combined=$(sort "$merged_paths" | uniq -c | sort -rn -k1,1 -k2,2 \
        | awk '{ $1=""; sub(/^ +/, ""); print }' | head -20)
      rm -f "$merged_paths"
    fi
  fi

  rank_paths_min_rank "$combined" "$source_path" "$synced_paths_json"
}

# grep_rank: learnings-only token-overlap retriever (no tier-1 INDEX.md).
grep_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  if [[ -z "$query" ]]; then echo ""; return; fi
  local tokens results
  tokens=$(extract_keywords "$query" 3)
  if [[ -z "$tokens" ]]; then echo ""; return; fi
  results=$(rank_paths_by_token_overlap_corpus "$tokens" learnings-only)
  rank_paths_min_rank "$results" "$source_path" "$synced_paths_json"
}

# Hardcoded fixture-seed paths (Plan §3, fixture self-check).
#
# LOAD-BEARING BOUND (#6736): the fixed length of this array — 7 — is what keeps
# $FIXTURE_ROWS off the argv ceiling. It is accumulated one row per seed and ends up
# bound as `--argjson fixture_seeds "$FIXTURE_ROWS"` on the report jq near the end of
# this file, i.e. as ONE argv argument. The kernel caps a SINGLE argv argument at
# MAX_ARG_STRLEN = 131,072 B (verified by bisect on this host: 131,071 B passes,
# 131,072 B fails E2BIG) — NOT `getconf ARG_MAX`, which is 2,097,152 B here.
#
# At ~155 B/row these 7 seeds measure ~1.1 KB, well under 1% of MAX_ARG_STRLEN. That
# is why this site is NOT converted to --rawfile: the conversion would be pure churn.
# But the bound is the ARRAY LENGTH, not anything structural. If this list is ever made
# corpus-driven (e.g. globbing knowledge-base/project/learnings/, ~1,986 files today),
# $FIXTURE_ROWS lands around 308 KB and this jq dies with `Argument list too long`.
# Growing it to a few dozen seeds is fine; sourcing it from the corpus is not — spool it
# to a file and bind with `--rawfile … | fromjson` first (see scripts/domain-model-drift.sh).
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
  # Cause categories for a learning unfindable at heavy paraphrase via
  # kb-search emulator. Inputs:
  #   $1 fm:        "yes" if file has YAML frontmatter
  #   $2 ps:        "yes" if file has a ## Problem section
  #   $3 grep_rank: rank under bare grep retriever (number or empty)
  # Resolution order (first match wins):
  #   missing-frontmatter — no frontmatter → description fallback chain
  #     starts at ## Problem / # Title / first-500
  #   content-shape       — has frontmatter but no ## Problem section
  #   retriever-miss      — has both, AND bare grep found it (so file is
  #     well-shaped and the bug is the kb-search emulator's two-tier strategy
  #     pushing tier-1 INDEX.md hits over content matches)
  #   unknown             — has both AND bare grep also missed (paraphrase
  #     drifted too far from any shared tokens)
  local fm="$1" ps="$2" grep_rank="${3:-}"
  if [[ "$fm" != "yes" ]]; then echo "missing-frontmatter"; return; fi
  if [[ "$ps" != "yes" ]]; then echo "content-shape"; return; fi
  if [[ -n "$grep_rank" ]]; then echo "retriever-miss"; return; fi
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

# self_test_flooding_pathology: synthesized regression test for the cap-20
# displacement bug that motivated #4119. 30 non-learning "session state"
# entries flood INDEX.md tier-1 for the keyword "schema drift". Under the
# pre-fix kbsearch_rank these displace the single matching learning out of
# the cap-20. Under the fix (cap-split 8/12 + tier-1 learnings scope) the
# target is recovered. cq-test-fixtures-synthesized-only.
self_test_flooding_pathology() {
  local KB_ROOT="$TMP_ROOT/kb-flood"
  mkdir -p "$KB_ROOT/knowledge-base/project/learnings" \
           "$KB_ROOT/knowledge-base/project/sessions"
  st_write "$KB_ROOT/knowledge-base/project/learnings/target.md" \
    '---' 'category: migrations' '---' '# Schema Drift Reasoning' \
    'discussing schema drift across pinned migrations.'
  local i
  for i in $(seq 1 30); do
    st_write "$KB_ROOT/knowledge-base/project/sessions/session-state-${i}.md" \
      "# Session State Schema Drift Notes ${i}" "Session $i unrelated content."
  done
  {
    echo '# Knowledge Base Index'; echo
    for i in $(seq 1 30); do
      echo "- [Session State Schema Drift Notes ${i}](project/sessions/session-state-${i}.md)"
    done
    echo '- [Schema Drift Reasoning](project/learnings/target.md)'
  } > "$KB_ROOT/knowledge-base/INDEX.md"
  (cd "$KB_ROOT" && git init -q && git add -A \
    && git -c user.email=t@t -c user.name=t commit -q -m fixture)
  local prev_repo="$REPO_ROOT" prev_idx="$INDEX_PATH"
  REPO_ROOT="$KB_ROOT"; INDEX_PATH="$KB_ROOT/knowledge-base/INDEX.md"
  local rk
  rk=$(kbsearch_rank "schema drift" "knowledge-base/project/learnings/target.md" "[]")
  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
  if [[ -n "$rk" && "$rk" -le 8 ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: flood-pathology: kbsearch_rank finds target despite 30 noise titles (rank=$rk)"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: flood-pathology: kbsearch_rank lost target (rank=${rk:-null})"
  fi
  REPO_ROOT="$prev_repo"; INDEX_PATH="$prev_idx"
}

# self_test_paraphrase_prepass: synthesized fixture for Stage 2 (#4176).
# Target learning uses canonical engineering vocabulary; query uses zero
# lexical overlap. Baseline kbsearch_rank MUST return null (negative
# control). Stage 2's union-of-paraphrases rank MUST recover the target
# at rank ≤ 8. Until PROMPT_QUERY_PARAPHRASE + union logic ship, assertion
# 2 fails by design (this is the RED state). cq-test-fixtures-synthesized-only.
self_test_paraphrase_prepass() {
  local KB_ROOT="$TMP_ROOT/kb-paraphrase"
  mkdir -p "$KB_ROOT/knowledge-base/project/learnings"
  st_write "$KB_ROOT/knowledge-base/project/learnings/orm-target.md" \
    '---' 'category: performance-issues' 'tags: [n+1]' '---' \
    '' '# ORM N+1 query under burst load' '' \
    'database connection pool exhaustion under burst load occurs when transaction allocation rate exceeds the configured maximum, producing TimeoutError on subsequent queries.'
  {
    echo '# Knowledge Base Index'; echo
    echo '- [ORM N+1 query under burst load](project/learnings/orm-target.md)'
  } > "$KB_ROOT/knowledge-base/INDEX.md"
  (cd "$KB_ROOT" && git init -q && git add -A \
    && git -c user.email=t@t -c user.name=t commit -q -m fixture)
  local prev_repo="$REPO_ROOT" prev_idx="$INDEX_PATH"
  REPO_ROOT="$KB_ROOT"; INDEX_PATH="$KB_ROOT/knowledge-base/INDEX.md"

  # Query has zero lexical overlap with content tokens. extract_keywords
  # drops <4-char tokens and stopwords; remaining tokens (saturating, workers)
  # do NOT appear in the corpus content (which uses "pool", "connection",
  # "exhaustion", "burst", "load", "transaction", "allocation"). Stage 2
  # paraphrase variants are required to bridge.
  local query="ORM saturating workers"
  local target="knowledge-base/project/learnings/orm-target.md"

  # Assertion 1 (negative control): kbsearch_rank with paraphrase explicitly
  # disabled via NO_PARAPHRASE=1 MUST return rank=null on this zero-overlap
  # query. At Phase 1 (no Stage 2 logic) this trivially passes because the
  # function has no paraphrase path. At Phase 2 GREEN, NO_PARAPHRASE=1 must
  # short-circuit Stage 2 and preserve the null baseline. This anchors the
  # `--no-paraphrase` opt-out behavior in CI.
  local rk_base
  rk_base=$(NO_PARAPHRASE=1 kbsearch_rank "$query" "$target" "[]")
  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
  if [[ -z "$rk_base" ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: paraphrase-prepass: NO_PARAPHRASE=1 baseline returns null on zero-overlap query (negative control)"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: paraphrase-prepass: NO_PARAPHRASE=1 baseline unexpectedly hit (rank=$rk_base); fixture is not zero-overlap"
  fi

  # Assertion 2: Stage 2 union-of-paraphrases MUST recover the target at
  # rank ≤ 8. At Phase 1 (no Stage 2 logic) this fails by design — the
  # function returns null. At Phase 2 GREEN, the < 5 baseline-hits trigger
  # fires, 3 paraphrase variants are generated via PROMPT_QUERY_PARAPHRASE,
  # and the union-by-path rank recovers the target.
  #
  # CURL_BIN is overridden by a stub that returns THREE DISTINCT paraphrases
  # (cycled via a tmp counter file) so the dedupe-by-exact-string-match branch
  # in kbsearch_rank's variant loop is actually exercised — three different
  # canonical phrasings, each lexically overlapping the orm-target.md corpus
  # content. ANTHROPIC_API_KEY is supplied locally for the kbsearch_rank
  # `[[ -n "${ANTHROPIC_API_KEY:-}" ]]` gate; restored to its prior state
  # post-test even when the operator had a real key set (the previous
  # `export` shape would have forwarded a real key into subsequent self-test
  # cases). cq-test-fixtures-synthesized-only.
  local stub_curl="$KB_ROOT/stub-curl.sh"
  local stub_counter="$KB_ROOT/stub-curl-counter"
  cat > "$stub_curl" <<STUB
#!/usr/bin/env bash
# Cycles through three distinct paraphrases (lexically overlap with corpus).
# Each call increments the counter file. The bench's anthropic_paraphrase
# strips newlines + writes the __HTTP_STATUS__ trailer; we mimic the shape.
COUNTER_FILE="${stub_counter}"
[[ -f "\$COUNTER_FILE" ]] || echo 0 > "\$COUNTER_FILE"
idx=\$(cat "\$COUNTER_FILE")
echo \$((idx + 1)) > "\$COUNTER_FILE"
case \$((idx % 3)) in
  0) phrase='database connection pool exhaustion under burst load' ;;
  1) phrase='transaction allocation timeout when concurrency exceeds maximum' ;;
  2) phrase='TimeoutError on queries during pool saturation' ;;
esac
printf '{"content":[{"text":"%s"}],"stop_reason":"end_turn"}\n' "\$phrase"
printf '__HTTP_STATUS__:200\n'
STUB
  chmod +x "$stub_curl"

  local rk_stage2 prev_curl_bin="$CURL_BIN"
  local prev_api_key_was_set=0 prev_api_key=""
  if [[ -n "${ANTHROPIC_API_KEY+x}" ]]; then
    prev_api_key_was_set=1
    prev_api_key="$ANTHROPIC_API_KEY"
  fi
  CURL_BIN="$stub_curl"
  ANTHROPIC_API_KEY="stub-key-self-test"
  rk_stage2=$(kbsearch_rank "$query" "$target" "[]")
  CURL_BIN="$prev_curl_bin"
  if (( prev_api_key_was_set == 1 )); then
    ANTHROPIC_API_KEY="$prev_api_key"
  else
    unset ANTHROPIC_API_KEY
  fi

  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
  if [[ -n "$rk_stage2" && "$rk_stage2" -le 8 ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: paraphrase-prepass: Stage 2 union-of-paraphrases recovers target (rank=$rk_stage2)"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: paraphrase-prepass: Stage 2 union-of-paraphrases lost target (rank=${rk_stage2:-null})"
  fi

  REPO_ROOT="$prev_repo"; INDEX_PATH="$prev_idx"
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

  # ── AC2-b': ## Problem is the file's TERMINAL section → last line preserved ──
  # Pre-fix regression: `sed '/^## Problem$/,/^## /p | sed 1d;$d'` dropped the
  # body's last line when no following `## ` heading existed. See
  # pattern-recognition review of PR #4045 (P1-3).
  st_write "$TMP_ROOT/b-terminal.md" \
    '---' \
    'title: foo' \
    'description:' \
    '---' \
    '' \
    '## Problem' \
    '' \
    'First line of problem body.' \
    'Last line of problem body (terminal section).'
  got="$(extract_problem_section "$TMP_ROOT/b-terminal.md")"
  st_assert_contains "AC2-b': terminal ## Problem preserves first line" "First line of problem body." "$got"
  st_assert_contains "AC2-b': terminal ## Problem preserves last line"  "Last line of problem body (terminal section)." "$got"

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
  st_assert "cause: no-fm → missing-frontmatter"     "missing-frontmatter" "$(classify_unfindable_cause "" "")"
  st_assert "cause: fm+no-ps → content-shape"        "content-shape"        "$(classify_unfindable_cause "yes" "")"
  st_assert "cause: fm+ps+grep-miss → unknown"       "unknown"              "$(classify_unfindable_cause "yes" "yes" "")"
  st_assert "cause: fm+ps+grep-found → retriever-miss" "retriever-miss"     "$(classify_unfindable_cause "yes" "yes" "3")"

  # ── build_close_comment_line embeds bucket + verbatim gh issue close ─────
  got="$(build_close_comment_line vindicate 0.83 knowledge-base/project/learnings/2026-05-19-retrieval-diagnostic-findings.md)"
  st_assert_contains "close-line: vindicate format" "gh issue close 4043 --comment" "$got"
  st_assert_contains "close-line: vindicate cites learning path" "2026-05-19-retrieval-diagnostic-findings.md" "$got"

  # ── extract_keywords: deterministic top-K longest non-stopword tokens ─────
  got="$(extract_keywords "The quick brown fox jumps over the lazy dog using react-resizable-panels" 3 | tr '\n' ',' | sed 's/,$//')"
  # Longest non-stopword tokens ≥4 chars: "react-resizable-panels"(22), "quick"(5), "brown"(5), "jumps"(5), "lazy"(4)
  # Top-3 longest: react-resizable-panels, quick|brown|jumps (tie at 5; awk sort -rn is stable on tie → first-seen wins)
  st_assert_contains "extract_keywords: longest token wins"  "react-resizable-panels" "$got"
  st_assert_contains "extract_keywords: returns 3 tokens"    "," "$got"  # at least 2 commas → 3 tokens
  # Stopword exclusion ("the", "over") + short-token exclusion ("fox", "dog" both <4)
  got="$(extract_keywords "the the the and and a" 3)"
  st_assert "extract_keywords: pure-stopword input → empty" "" "$got"
  # Numeric-only tokens dropped
  got="$(extract_keywords "1234 5678 schema migration backfill" 3 | tr '\n' ',' | sed 's/,$//')"
  st_assert_contains "extract_keywords: numeric-only tokens dropped" "migration" "$got"
  st_assert_contains "extract_keywords: keeps schema" "schema" "$got"
  case ",$got," in *",1234,"*) SELF_TEST_FAIL=$((SELF_TEST_FAIL+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); echo "  FAIL: numeric 1234 leaked into tokens";;
                   *) SELF_TEST_PASS=$((SELF_TEST_PASS+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); echo "  PASS: numeric-only tokens NOT in output";;
  esac

  # ── Token-overlap retriever: end-to-end with synthesized mini-corpus ──────
  local KB_ROOT="$TMP_ROOT/kb"
  mkdir -p "$KB_ROOT/knowledge-base/project/learnings"
  st_write "$KB_ROOT/knowledge-base/project/learnings/alpha.md" \
    '---' \
    'description: pinned migration causes drift in production' \
    '---' \
    '# Alpha Migration' \
    'When you apply a pinned migration the downstream schema drifts.'
  st_write "$KB_ROOT/knowledge-base/project/learnings/beta.md" \
    '---' \
    'description: stopword stuffing in a beta retrieval test' \
    '---' \
    '# Beta Lookup' \
    'beta covers retrieval lookups across the corpus.'
  st_write "$KB_ROOT/knowledge-base/project/learnings/gamma.md" \
    '---' \
    'description: workflow gate enforces compounding learning capture' \
    '---' \
    '# Gamma Compounding' \
    'workflow gate ensures every solution compounds into a learning file.'
  # gitify the kb so `git grep` works
  (cd "$KB_ROOT" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "fixture")
  st_write "$KB_ROOT/knowledge-base/INDEX.md" \
    '# Knowledge Base Index' \
    '' \
    '- [Alpha Migration](project/learnings/alpha.md)' \
    '- [Beta Lookup](project/learnings/beta.md)' \
    '- [Gamma Compounding](project/learnings/gamma.md)'

  # Run our retrievers against the mini-corpus by re-exporting paths.
  local prev_repo="$REPO_ROOT" prev_idx="$INDEX_PATH"
  REPO_ROOT="$KB_ROOT"; INDEX_PATH="$KB_ROOT/knowledge-base/INDEX.md"
  (cd "$KB_ROOT" && git add -A && git -c user.email=t@t -c user.name=t commit -q --amend --no-edit)

  # Query "pinned migration drift" — should match alpha first via token overlap
  local rk
  rk="$(kbsearch_rank "pinned migration drift" "knowledge-base/project/learnings/alpha.md" "[]")"
  st_assert "token-overlap: alpha findable at rank 1 via kbsearch" "1" "$rk"

  # Query "retrieval lookups corpus" — should match beta
  rk="$(kbsearch_rank "retrieval lookups corpus" "knowledge-base/project/learnings/beta.md" "[]")"
  st_assert "token-overlap: beta findable via kbsearch" "1" "$rk"

  # Paraphrase-style query (light) — synonym substitution should still find alpha
  rk="$(grep_rank "applying a pinned migration triggers drift" "knowledge-base/project/learnings/alpha.md" "[]")"
  if [[ -n "$rk" && "$rk" -le 5 ]]; then
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: grep_rank: synonym-substituted query finds alpha (rank=$rk)"
  else
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: grep_rank: synonym-substituted query missed alpha (rank=$rk)"
  fi

  # Empty / pure-stopword query → null rank (not crash)
  rk="$(kbsearch_rank "the and a" "knowledge-base/project/learnings/alpha.md" "[]")"
  st_assert "token-overlap: pure-stopword query → null rank" "" "$rk"

  # min-rank semantics with synced_to: synthesize a second file containing alpha's tokens
  st_write "$KB_ROOT/knowledge-base/project/learnings/alpha-mirror.md" \
    '---' \
    'description: pinned migration drift mirror filing' \
    '---' \
    '# Alpha Mirror' \
    'a sibling filing about pinned migration drift.'
  (cd "$KB_ROOT" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "mirror")
  rk="$(kbsearch_rank "pinned migration drift" "knowledge-base/project/learnings/alpha.md" '["knowledge-base/project/learnings/alpha-mirror.md"]')"
  if [[ -n "$rk" && "$rk" -le 5 ]]; then
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_PASS=$((SELF_TEST_PASS+1))
    echo "  PASS: min-rank synced_to: best position across both filings (rank=$rk)"
  else
    SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1)); SELF_TEST_FAIL=$((SELF_TEST_FAIL+1))
    echo "  FAIL: min-rank synced_to (rank=$rk)"
  fi

  REPO_ROOT="$prev_repo"; INDEX_PATH="$prev_idx"

  # ── Bug-1 regression: jq null-rank construction emits a row ───────────────
  # The pre-fix shape silently dropped null-rank rows from ranks.ndjson. The
  # post-fix shape uses --argjson rank null and ALWAYS emits exactly one row.
  local row_null row_num
  row_null=$(jq -nc --arg path "x" --arg intensity "heavy" --arg retriever "kbsearch" --argjson rank null \
    '{path:$path,intensity:$intensity,retriever:$retriever,rank:$rank}')
  row_num=$(jq -nc --arg path "x" --arg intensity "heavy" --arg retriever "kbsearch" --argjson rank 7 \
    '{path:$path,intensity:$intensity,retriever:$retriever,rank:$rank}')
  st_assert "bug-1 fix: null-rank row emitted" '{"path":"x","intensity":"heavy","retriever":"kbsearch","rank":null}' "$row_null"
  st_assert "bug-1 fix: numeric-rank row emitted" '{"path":"x","intensity":"heavy","retriever":"kbsearch","rank":7}' "$row_num"

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

  # ── Flooding-pathology regression (#4119): cap-20 displacement under noise ──
  self_test_flooding_pathology

  # ── Paraphrase pre-pass (#4176 Stage 2): union-of-paraphrases recovers zero-overlap target ──
  self_test_paraphrase_prepass

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

# API-key check is deferred until we know Phase 2 will actually run. A
# cache-hit rerun (--cache-paraphrases <path> covering the full corpus)
# does NOT need ANTHROPIC_API_KEY because Phase 2 short-circuits before
# any curl. Without this deferral, a workstation that rotated its API
# key out of env crashes mid-run on a cache-hit invocation that would
# have completed without spending a cent. See pattern-recognition review
# of PR #4045 (P1-1).
WILL_NEED_API_KEY=1
if [[ -n "$CACHE_PARAPHRASES" && -s "$CACHE_PARAPHRASES" ]]; then
  WILL_NEED_API_KEY=0
fi
if (( WILL_NEED_API_KEY == 1 )); then
  require_api_key
fi

# ─── Phase 1: corpus indexing ──────────────────────────────────────────────
CORPUS_NDJSON=$(mktemp)
# Paraphrases land in the cache path if supplied (durable across reruns —
# avoids re-spending Anthropic budget on Phase 3 iterations); otherwise a
# tempfile that EXIT-trap-rms.
if [[ -n "$CACHE_PARAPHRASES" ]]; then
  PARAPHRASES_NDJSON="$CACHE_PARAPHRASES"
else
  PARAPHRASES_NDJSON=$(mktemp)
fi
RANKS_NDJSON=$(mktemp)
if [[ -n "$CACHE_PARAPHRASES" ]]; then
  trap 'rm -f "$CORPUS_NDJSON" "$RANKS_NDJSON"' EXIT
else
  trap 'rm -f "$CORPUS_NDJSON" "$PARAPHRASES_NDJSON" "$RANKS_NDJSON"' EXIT
fi

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
API_CALLS=0; API_RETRIES=0; API_ERRORS=0
i=0

# Cache-hit shortcut: if the cache file exists and covers every corpus path,
# skip the (~$3, ~50 min) Phase 2 regeneration entirely. Defensive coverage
# check: paths in cache must be a superset of paths in corpus; cache lines
# must have non-empty light + heavy strings (excludes prior aborted runs).
PARAPHRASE_CACHE_HIT=0
if [[ -n "$CACHE_PARAPHRASES" && -s "$PARAPHRASES_NDJSON" ]]; then
  CACHE_COVERAGE=$(jq -s --slurpfile c <(jq -s . "$CORPUS_NDJSON") '
    ($c[0] | map(.path)) as $corpus_paths
    | (map(select(.light != "" and .heavy != "")) | map(.path)) as $cache_paths
    | ($corpus_paths - $cache_paths) | length
  ' < "$PARAPHRASES_NDJSON" 2>/dev/null || echo "999999")
  if [[ "$CACHE_COVERAGE" == "0" ]]; then
    echo "Phase 2: paraphrase cache HIT ($PARAPHRASES_NDJSON covers all $TOTAL_COUNT files) — skipping Anthropic calls."
    PARAPHRASE_CACHE_HIT=1
  else
    echo "Phase 2: paraphrase cache PARTIAL ($CACHE_COVERAGE files missing) — regenerating from scratch."
  fi
fi

if (( PARAPHRASE_CACHE_HIT == 0 )); then
echo "Phase 2: paraphrase generation (sync, ~50 min for full corpus)"
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
fi  # PARAPHRASE_CACHE_HIT == 0

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
    # Bug-fix: pass rank as --argjson (null or number). The previous shape
    # `--arg rank "$rk" | ($rank|select(length>0)|tonumber? // null)` silently
    # produced NO output when $rk was "", so null-rank rows never landed in
    # ranks.ndjson — collapsing R@5(light|heavy) to 0 for the wrong reason.
    rk_kb_arg="${rk_kb:-null}"
    rk_grep_arg="${rk_grep:-null}"
    jq -nc --arg path "$rel" --arg intensity "$intensity" --arg retriever "kbsearch" --argjson rank "$rk_kb_arg" \
      '{path:$path,intensity:$intensity,retriever:$retriever,rank:$rank}' >> "$RANKS_NDJSON"
    jq -nc --arg path "$rel" --arg intensity "$intensity" --arg retriever "grep"     --argjson rank "$rk_grep_arg" \
      '{path:$path,intensity:$intensity,retriever:$retriever,rank:$rank}' >> "$RANKS_NDJSON"
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

# 4-decimal rounded versions for human display. The unrounded jq-emitted
# values stay in the sibling JSON for downstream tooling; only the markdown
# learning shows the readable form.
round4() { awk -v v="$1" 'BEGIN { printf "%.4f", v }'; }
R5_ID_KB_R="$(round4 "$R5_ID_KB")"; R5_LT_KB_R="$(round4 "$R5_LT_KB")"; R5_HV_KB_R="$(round4 "$R5_HV_KB")"
R5_ID_GR_R="$(round4 "$R5_ID_GR")"; R5_LT_GR_R="$(round4 "$R5_LT_GR")"; R5_HV_GR_R="$(round4 "$R5_HV_GR")"
R10_ID_KB_R="$(round4 "$R10_ID_KB")"; R10_LT_KB_R="$(round4 "$R10_LT_KB")"; R10_HV_KB_R="$(round4 "$R10_HV_KB")"
R10_ID_GR_R="$(round4 "$R10_ID_GR")"; R10_LT_GR_R="$(round4 "$R10_LT_GR")"; R10_HV_GR_R="$(round4 "$R10_HV_GR")"
MRR_ID_KB_R="$(round4 "$MRR_ID_KB")"; MRR_LT_KB_R="$(round4 "$MRR_LT_KB")"; MRR_HV_KB_R="$(round4 "$MRR_HV_KB")"
MRR_ID_GR_R="$(round4 "$MRR_ID_GR")"; MRR_LT_GR_R="$(round4 "$MRR_LT_GR")"; MRR_HV_GR_R="$(round4 "$MRR_HV_GR")"

# Skill-ROI interpretation depends on sign — kb-search outperforming grep
# (positive) is the "skill earns its keep" finding; underperforming grep
# (negative) is the "two-tier strategy hurts at scale" finding.
if awk -v g="$GAP_SKILL_ROI" 'BEGIN { exit !(g+0 > 0) }'; then
  GAP_SKILL_ROI_NOTE="positive — kb-search outperforms bare grep at heavy paraphrase."
else
  GAP_SKILL_ROI_NOTE="**negative** — bare grep outperforms kb-search at heavy paraphrase. The two-tier strategy's INDEX.md tier-1 hits displace corpus content hits from the cap-20, hurting recall on hard queries."
fi

WORST_N_WITH_CAUSE="[]"
# Cause classification (resolution order, first match wins):
#   missing-frontmatter → no YAML frontmatter; description fallback chain
#     starts at ## Problem / # Title / first-500
#   content-shape       → has frontmatter but no ## Problem section
#   retriever-miss      → has both, AND bare grep found it (kb-search-strategy
#     fails on a well-shaped learning; bench is exposing the two-tier strategy
#     not the learning's content)
#   unknown             → has both AND bare grep also missed (paraphrase
#     drifted too far from any shared tokens — methodology limit, not
#     learning-shape problem)
# See pattern P2 in code-quality + data-integrity review of PR #4045 — the
# previous build collapsed every fm+ps row to "unknown" which read as
# "diagnostic failure" instead of "kb-search-strategy lost to grep on these
# queries", masking the bench's most actionable signal.
WORST_N_WITH_CAUSE=$(jq -s \
  --slurpfile corpus <(jq -s . "$CORPUS_NDJSON") \
  --slurpfile ranks <(jq -s . "$RANKS_NDJSON") '
  ($corpus[0] | map({(.path): {fm: .has_frontmatter, ps: .has_problem_section}}) | add) as $idx
  | ($ranks[0] | map(select(.intensity == "heavy" and .retriever == "grep"))
                 | map({(.path): .rank}) | add) as $grep_idx
  | map(select(.intensity == "heavy" and .retriever == "kbsearch" and .rank == null))
  # LOAD-BEARING BOUND (#6736): this truncation to 20 rows is the only thing keeping
  # $WORST_N_WITH_CAUSE off the argv ceiling. The result is bound as
  # `--argjson worst_n "$WORST_N_WITH_CAUSE"` on the report jq near the end of this
  # file — ONE argv argument, and the kernel caps a SINGLE argv argument at
  # MAX_ARG_STRLEN = 131,072 B (bisected on this host: 131,071 B passes, 131,072 B
  # fails E2BIG). NOT `getconf ARG_MAX` (2,097,152 B here); 6% of ARG_MAX still dies.
  #
  # 20 rows measure 4,156 B — 3% of MAX_ARG_STRLEN, which is why this site is NOT
  # converted to --rawfile (churn). The input to this filter is the FULL corpus of
  # kbsearch misses, drawn from ~1,986 learnings; without this cap a bad-retrieval run
  # can put thousands of rows on argv and kill the report with `Argument list too long`
  # AFTER the entire (paid, API-calling) bench has already run. Widening the window is
  # fine up to ~500 rows; removing the cap, or making N corpus-derived, requires
  # spooling to a file and binding `--rawfile … | fromjson` (see domain-model-drift.sh).
  | .[0:20]
  | map(
      .path as $p
      | {
          path: $p,
          rank_heavy_kbsearch: null,
          rank_heavy_grep: ($grep_idx[$p] // null),
          cause: (
            if ($idx[$p].fm // "no") != "yes" then "missing-frontmatter"
            elif ($idx[$p].ps // "no") != "yes" then "content-shape"
            elif ($grep_idx[$p] // null) != null then "retriever-miss"
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
    schema: 2,
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
    bucket:         $bucket,
    r5_identity:    $r5_ikb,
    r5_light:       $r5_lkb,
    r5_heavy:       $r5_hkb
  }' > "$JSON_TMP"
mv "$JSON_TMP" "$REPO_ROOT/$JSON_PATH"
echo "  wrote $JSON_PATH"

CLOSE_LINE="$(build_close_comment_line "$BUCKET" "$R5_HV_KB_R" "$LEARNING_PATH")"

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

Bucket: **\`$BUCKET\`**. \`R@5(heavy, kb-search) = $R5_HV_KB_R\` across $TOTAL_COUNT learnings.

EOF
  case "$BUCKET" in
    vindicate)        echo "**Recommended action:** \`Closes #4043\`. No follow-up. The 2026-04-07 file-based-retrieval framing is vindicated by evidence." ;;
    surface-rewrites) echo "**Recommended action:** \`Closes #4043\`. File ONE follow-up issue with the worst-N list below as acceptance-criteria checklist." ;;
    reopen-rag)       echo "**Recommended action:** \`Closes #4043\`. File ONE follow-up issue to reopen the 2026-04-07 RAG/embeddings decision." ;;
  esac
  cat <<EOF

## Methodology

Per the plan (\`knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md\`) and post-first-run revision (see commit \`3fb52a05\`):

- **Three paraphrase intensities** generated per learning: \`identity\` (ground-truth verbatim, no LLM), \`light\` (synonym substitution via Haiku), \`heavy\` (different framing via Haiku).
- **Keyword extraction from each query.** The retriever does NOT pass the full paraphrase sentence to \`grep -F\` (the original plan did; that yielded vacuous 0 because sentence-paraphrases never substring-match verbatim source text). Instead, a bash heuristic extracts the top-3 longest non-stopword tokens (≥4 chars, drop all-numeric, dedup) from each query.
- **Token-overlap ranking.** Each candidate path is scored by the number of distinct extracted tokens that substring-match it (case-insensitive). Sort by score desc, ties broken by lexicographic path order, cap top-20.
- **Two retrievers** exercised per intensity: a bash emulator of kb-search's two-tier strategy (INDEX.md title-line token-overlap as tier-1 → KB-wide content token-overlap as tier-2, combined unique cap-20), and a learnings-only baseline (single-tier token-overlap against \`knowledge-base/project/learnings/\`).
- **min-rank synced_to semantics:** if a learning declares \`synced_to:\`, the source's rank is the BEST (lowest) position across {source_path, synced_to[…]} in the retriever's combined output. This biases R@5 upward vs. the strict "source-only" definition and is documented here so a future reader does NOT conflate the two.
- **kb-search is a strategy, not a skill call.** The bench replicates the two-tier strategy in bash because (a) the skill is a Markdown prompt agents interpret, not a CLI, and (b) the strategy is the stable interface — its grep flags survive Markdown wording changes.
- **Headline numbers are a proxy, not a direct measurement.** Token-overlap retrieval is an upper-bound proxy of true \`kb-search\` skill recall. The skill itself takes a single \`\$KEYWORD\` argument; the bench's top-3-token-overlap shape is more permissive than a single-keyword call would be. Read R@5 as "the skill's recall ceiling under a charitable keyword-extraction assumption", not as "the skill's recall when used in practice."

## Results

### Corpus-wide R@5 / R@10 / MRR (6 cells each)

|                      | kb-search    | bare grep    |
|---                   |---           |---           |
| **R@5 identity**     | $R5_ID_KB_R  | $R5_ID_GR_R  |
| **R@5 light**        | $R5_LT_KB_R  | $R5_LT_GR_R  |
| **R@5 heavy**        | $R5_HV_KB_R  | $R5_HV_GR_R  |
| **R@10 identity**    | $R10_ID_KB_R | $R10_ID_GR_R |
| **R@10 light**       | $R10_LT_KB_R | $R10_LT_GR_R |
| **R@10 heavy**       | $R10_HV_KB_R | $R10_HV_GR_R |
| **MRR identity**     | $MRR_ID_KB_R | $MRR_ID_GR_R |
| **MRR light**        | $MRR_LT_KB_R | $MRR_LT_GR_R |
| **MRR heavy**        | $MRR_HV_KB_R | $MRR_HV_GR_R |

### Gap signals

- **Honesty gap (R@5 identity − heavy, kb-search):** $GAP_HONESTY — if < 0.05 the heavy paraphrase is too close to identity and prompts need tightening before treating corpus numbers as load-bearing.
- **Skill-ROI gap (R@5 heavy: kb-search − grep):** $GAP_SKILL_ROI — $GAP_SKILL_ROI_NOTE

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

## Bench Revision History

The first \`--confirm\` run on 2026-05-19 produced bucket=\`reopen-rag\` with R@5(light|heavy, *) ≡ 0 — degenerate. Three independent bugs were discovered and fixed before the rerun whose numbers appear above:

1. **jq null-rank drop** (code). The per-row writer used \`--arg rank "" | select(length>0)|tonumber? // null\` which silently emitted NO output when rank was empty — null-rank rows never landed in \`ranks.ndjson\`. Fixed by switching to \`--argjson rank null\` (or numeric).
2. **Sentence-as-grep-query** (methodology). The plan §Phase 3 passed the full paraphrase sentence to \`grep -F\`. Real kb-search consumes a short \$KEYWORD; a 1-2 sentence paraphrase never substring-matches verbatim source text. Fixed by adding bash-side keyword extraction (top-3 longest non-stopword tokens, ≥4 chars, drop all-numeric, dedup) + token-overlap ranking.
3. **Git pathspec coverage** (code). The pathspec \`'knowledge-base/project/learnings/**/*.md'\` matched ONLY files in subdirs (gobwas \`**\` requires intermediate dirs — same trap as \`2026-03-21-lefthook-gobwas-glob-double-star.md\`). The first run searched 301/1117 files (27% of corpus). Fixed by switching to directory-prefix pathspec + \`:(exclude,glob)**/archive/**\` long-form exclude.

All three fixes shipped together in commit \`3fb52a05\` with 13 new self-tests. The 7/7-fixture-seed-null methodology-suspect signal that fired on the first run no longer fires (3/7 seeds found at heavy_kbsearch, ranks 1, 7, 16).
EOF
} > "$LEARNING_TMP"
mv "$LEARNING_TMP" "$REPO_ROOT/$LEARNING_PATH"
echo "  wrote $LEARNING_PATH"

echo
echo "================================================================"
echo "BUCKET: $BUCKET"
echo "R5_HEAVY_KBSEARCH: $R5_HV_KB_R"
echo "CLOSE_CMD: $CLOSE_LINE"
echo "================================================================"
echo
echo "Run the CLOSE_CMD verbatim before marking PR ready."
