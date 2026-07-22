#!/usr/bin/env bash
# On-demand + local aggregator: parse AGENTS.md rule IDs + .claude/.rule-incidents.jsonl
# and write knowledge-base/project/rule-metrics.json.
#
# Output schema (plan Phase 5):
#   {
#     "schema": 1,
#     "generated_at": "<ISO 8601>",
#     "rules": [{id, section, hit_count, bypass_count, prevented_errors,
#                last_hit, first_seen}, ...],
#     "summary": {total_rules_tagged, rules_unused_over_8w, rules_bypassed_over_baseline,
#                 orphan_rule_ids}
#   }
#
# Honors $INCIDENTS_REPO_ROOT for tests (falls back to the repo this script
# lives in).
#
# Flags:
#   --dry-run   print the JSON to stdout; do not write rule-metrics.json
#               and do not rotate jsonl.
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rule-metrics-constants.sh
source "$SCRIPT_DIR/lib/rule-metrics-constants.sh"

REPO_ROOT="${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

AGENTS_MD="$REPO_ROOT/AGENTS.md"
INCIDENTS="$REPO_ROOT/.claude/.rule-incidents.jsonl"
OUT="$REPO_ROOT/knowledge-base/project/rule-metrics.json"

[[ -f "$AGENTS_MD" ]] || { echo "ERROR: $AGENTS_MD not found" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# Threshold: rules with no hits in N weeks considered "unused" (default 8).
UNUSED_WEEKS=$UNUSED_WEEKS_DEFAULT
UNUSED_CUTOFF_EPOCH=$(( $(date -u +%s) - UNUSED_WEEKS * 7 * 86400 ))

# Work area — TSV materialization plus the final-report tmpfile live here.
_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

# --- Parse AGENTS.md into id + section tuples -----------------------------
# Output format (one line per rule): "<id>\t<section>\t<prefix>"
rules_tsv=$(awk -v plen="$RULE_PREFIX_LEN" '
  /^## / { section=$0; sub(/^## /, "", section); next }
  section != "" && /^- / {
    # Extract the first [id: <slug>] on the line
    if (match($0, /\[id: [a-z0-9-]+\]/)) {
      id = substr($0, RSTART+5, RLENGTH-6)
      # First ~plen chars of the bullet body for prefix/forensics
      line = $0
      sub(/^- /, "", line)
      sub(/ ?\[id:[^]]+\]/, "", line)
      prefix = substr(line, 1, plen)
      gsub(/\t/, " ", prefix)
      printf "%s\t%s\t%s\n", id, section, prefix
    }
  }
' "$AGENTS_MD")

# Materialize the TSV to a real file — jq --rawfile is happier with a path
# than a process substitution when the producer is long-lived.
rules_tsv_file="$_tmpdir/rules.tsv"
printf '%s' "$rules_tsv" > "$rules_tsv_file"

# Guard against an AGENTS.md that parses to zero rules — otherwise the
# aggregator would silently emit a valid-but-empty report and callers
# (compound SKILL.md step 8, /soleur:sync rule-prune) would see
# `total_rules_tagged: 0` with no error signal. This is a malformed-input
# condition, not a normal state.
if [[ ! -s "$rules_tsv_file" ]]; then
  echo "ERROR: $AGENTS_MD parsed to zero rules — check section headers and [id: ...] tags." >&2
  exit 3
fi

# --- Counts from jsonl ----------------------------------------------------
# Per-line parse via `jq -R 'fromjson?'` so a single malformed line from a
# crash-mid-write or OOM does NOT abort the whole aggregation. Bad
# lines are dropped with a stderr warning; valid lines are still counted.
#
# Archive-spanning input (#3508): per-write rotation moves data from the
# active file into `.rule-incidents-YYYY-MM*.jsonl.gz`. Merge active + all
# archives into a single materialized tmpfile so the aggregator window is not
# truncated by rotation cadence. Order doesn't matter — counts are commutative
# and `last_hit`/`first_seen` are computed from event timestamps.
INCIDENTS_MERGED="$_tmpdir/incidents-merged.jsonl"
: > "$INCIDENTS_MERGED"
[[ -s "$INCIDENTS" ]] && cat "$INCIDENTS" >> "$INCIDENTS_MERGED"
for _gz in "$REPO_ROOT"/.claude/.rule-incidents-*.jsonl.gz; do
  [[ -e "$_gz" ]] || continue
  zcat "$_gz" 2>/dev/null >> "$INCIDENTS_MERGED" || true
done

jq_counts='{}'
# Drop-sentinel counts (issue #3509). Sentinels carry `error` but no
# `rule_id` / `event_type`; the valid_stream filter below excludes them
# from the reduce. A separate jq pass populates these counts.
drops_counts_json='{}'
# Initialized at top level so the no-op guard (issue #6042) can read them on
# the empty / absent / sentinel-only path without a `set -euo pipefail`
# unbound-variable abort; the `[[ -s "$INCIDENTS_MERGED" ]]` block below only
# assigns them when the merged log is non-empty.
valid_lines=0
drops_total=0
if [[ -s "$INCIDENTS_MERGED" ]]; then
  total_lines=$(wc -l < "$INCIDENTS_MERGED")
  # Tolerant parse: fromjson? yields null on parse failure; select(.) drops
  # nulls. select(.schema == 1) pins the consumer-side schema gate (issue
  # #3509 plan Sharp Edge #2). select(.rule_id != null) drops sentinels —
  # they have `error` but no `rule_id`, and entering the reduce would create
  # a `"null"` key that poisons $known_ids and trips the orphan gate.
  valid_stream=$(jq -R 'fromjson? | select(.) | select(.schema == 1) | select(.rule_id != null)' \
    < "$INCIDENTS_MERGED" 2>/dev/null || echo "")
  valid_lines=0
  if [[ -n "$valid_stream" ]]; then
    # `|| echo 0` + `${…:-0}` protect the arithmetic below from a failed
    # second-stage jq (e.g., missing jq binary, corrupt internals). Both
    # guards are defensive — a successful first-stage `jq -R` makes a
    # broken second-stage parse exceedingly unlikely.
    valid_lines=$(echo "$valid_stream" | jq -s 'length' 2>/dev/null || echo 0)
    valid_lines=${valid_lines:-0}
  fi
  # Sentinel counts — separate jq pass over the same merged stream. The
  # `select(.schema == 1)` gate matches the valid_stream filter symmetrically
  # so a future schema-v2 sentinel doesn't silently bucket into v1 counters.
  # Counts are total (active + archives). Computed BEFORE the bad_lines
  # warning so we can net sentinels out — they're filtered intentionally,
  # not malformed.
  drops_counts_json=$(jq -R -s '
    [ split("\n")[]
      | select(length > 0)
      | (fromjson? // empty)
      | select(.schema == 1)
      | select(.error != null)
    ]
    | reduce .[] as $e ({};
        .[$e.error] = ((.[$e.error] // 0) + 1)
      )
  ' < "$INCIDENTS_MERGED" 2>/dev/null || echo '{}')
  drops_counts_json=${drops_counts_json:-'{}'}
  drops_total=$(jq -r 'add // 0' <<< "$drops_counts_json" 2>/dev/null || echo 0)
  drops_total=${drops_total:-0}
  bad_lines=$(( total_lines - valid_lines - drops_total ))
  if [[ "$bad_lines" -lt 0 ]]; then
    # Negative arithmetic implies a counting drift (sentinels overcounted
    # vs total_lines, e.g., a torn sentinel that wc-counted as 1 line but
    # also matched the drops filter). Surface it instead of silently
    # masking — exactly the silent-data-corruption class this PR exists to
    # prevent.
    echo "::warning::bad_lines underflow ($bad_lines) on $INCIDENTS — total=$total_lines valid=$valid_lines drops=$drops_total. Clamping to 0." >&2
    bad_lines=0
  fi
  if [[ "$bad_lines" -gt 0 ]]; then
    # GitHub Actions picks up `::warning::` for workflow annotations; harmless locally.
    echo "::warning::Dropped $bad_lines malformed line(s) from $INCIDENTS (+ archives) (kept $valid_lines)" >&2
  fi
  if [[ "$drops_total" -gt 0 ]]; then
    # Visibility for interactive consumers (agent debugging, manual cron
    # runs). Filter is invisible to the script's stdout otherwise.
    drops_breakdown=$(jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ")' <<< "$drops_counts_json" 2>/dev/null || echo "")
    echo "Filtered $drops_total telemetry-drop sentinel row(s) from $INCIDENTS (+ archives) — see summary.drops_*_count [${drops_breakdown}]" >&2
  fi
  if [[ "$valid_lines" -gt 0 ]]; then
    # fire_count increments on any recognized event_type (deny, bypass,
    # applied, warn). Unknown event_types do not increment fire_count —
    # they are silently skipped so a typo'd emit call does not inflate the
    # "rule fired" signal used by rule-prune.
    jq_counts=$(echo "$valid_stream" | jq -s '
      reduce .[] as $e ({};
        (.[$e.rule_id] //= {hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, last_hit:null, first_seen:null}) |
        (if $e.event_type == "deny"    then .[$e.rule_id].hit_count     += 1 else . end) |
        (if $e.event_type == "bypass"  then .[$e.rule_id].bypass_count  += 1 else . end) |
        (if $e.event_type == "applied" then .[$e.rule_id].applied_count += 1 else . end) |
        (if $e.event_type == "warn"    then .[$e.rule_id].warn_count    += 1 else . end) |
        (if ($e.event_type == "deny" or $e.event_type == "bypass" or $e.event_type == "applied" or $e.event_type == "warn")
           then .[$e.rule_id].fire_count += 1 else . end) |
        (if .[$e.rule_id].first_seen == null or ($e.timestamp < .[$e.rule_id].first_seen)
           then .[$e.rule_id].first_seen = $e.timestamp else . end) |
        (if .[$e.rule_id].last_hit   == null or ($e.timestamp > .[$e.rule_id].last_hit)
           then .[$e.rule_id].last_hit   = $e.timestamp else . end)
      )
    ')
  fi
fi

# --- Stitch rules + counts into the final report --------------------------
# Pipeline split into three sequential jq stages, each gated by `jq empty`
# so an off-by-one in one stage fails loudly instead of producing bogus JSON.
#   Stage A (_parse_rules) — raw TSV → $rules array
#   Stage B (_enrich)      — $rules + $counts → $enriched
#   Stage C (_summarize)   — $enriched → final top-level object
#
# ARGV CEILING (#6736). Every inter-stage payload below is spooled to a file in
# $_tmpdir and bound with `--rawfile … | fromjson`, NOT `--argjson`. A shell
# variable bound via --argjson becomes ONE argv argument, and the kernel caps a
# SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B — verified by bisect on this
# host: 131,071 B passes, 131,072 B fails E2BIG. This is NOT `getconf ARG_MAX`
# (2,097,152 B, the argv+envp total); a payload at 6% of ARG_MAX still dies.
#
# Measured pre-fix at 101 tagged rules: stage_rules 13,063 B and stage_enriched
# 31,445 B with counts empty — 35,081 B once last_hit/first_seen timestamps are
# populated, i.e. 27% of the ceiling at ~347 B/rule. That collides at ~378 rules,
# and AGENTS.md gains rules every compound cycle, so the old form was on a timer.
# file I/O has no per-argument limit, so the ceiling is gone.
#
# Lifts the in-file precedent one screen up: `--rawfile rules_tsv "$rules_tsv_file"`.
# (--slurpfile was rejected for the JSON payloads: each is a single top-level
# array, so it would bind as [[…]] and yield a SILENT `| length == 1` undercount
# rather than an error. `--rawfile … | fromjson` binds the value itself.)
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# $jq_counts is keyed by rule_id — it grows with the rule set AND with orphan
# rule_ids from the incident log, so it is spooled too, not just $enriched.
counts_file="$_tmpdir/stage-counts.json"
printf '%s' "$jq_counts" > "$counts_file"

stage_rules_file="$_tmpdir/stage-rules.json"
jq -n \
  --rawfile rules_tsv "$rules_tsv_file" '
    $rules_tsv
    | split("\n")
    | map(select(length > 0))
    | map(split("\t"))
    | map({id: .[0], section: .[1], rule_text_prefix: .[2]})
  ' > "$stage_rules_file"
jq empty < "$stage_rules_file" >/dev/null 2>&1 || { echo "ERROR: stage A (rules parse) malformed" >&2; exit 4; }

stage_enriched_file="$_tmpdir/stage-enriched.json"
jq -n \
  --rawfile rules_json "$stage_rules_file" \
  --rawfile counts_json "$counts_file" '
    ($rules_json | fromjson) as $rules
    | ($counts_json | fromjson) as $counts
    | $rules
    | map(
        . as $r
        | ($counts[$r.id] // {hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, last_hit:null, first_seen:null}) as $c
        | {
            id: $r.id,
            section: $r.section,
            hit_count: $c.hit_count,
            bypass_count: $c.bypass_count,
            applied_count: $c.applied_count,
            warn_count: $c.warn_count,
            fire_count: $c.fire_count,
            prevented_errors: ([$c.hit_count - $c.bypass_count, 0] | max),
            last_hit: $c.last_hit,
            first_seen: $c.first_seen,
            rule_text_prefix: $r.rule_text_prefix
          }
      )
    | sort_by(.fire_count, .id)
  ' > "$stage_enriched_file"
jq empty < "$stage_enriched_file" >/dev/null 2>&1 || { echo "ERROR: stage B (enrich) malformed" >&2; exit 4; }

# $drops and $cutoff and $schema stay on argv: drops is keyed by a closed error
# enum (a handful of keys) and the other two are scalars — none can approach
# MAX_ARG_STRLEN. $enriched and $counts are the ones that scale with the rule set.
report=$(jq -n \
  --argjson schema "$SCHEMA_VERSION" \
  --arg generated_at "$GENERATED_AT" \
  --rawfile enriched_json "$stage_enriched_file" \
  --rawfile counts_json "$counts_file" \
  --argjson drops "$drops_counts_json" \
  --argjson cutoff "$UNUSED_CUTOFF_EPOCH" '
    ($enriched_json | fromjson) as $enriched
    | ($counts_json | fromjson) as $counts
    # Orphan events: rule_ids in the jsonl that don'"'"'t match any AGENTS.md id.
    # Surfacing these prevents silent data loss when a hook emits a rule_id
    # that was renamed / removed / never tagged (e.g., historical sentinel names).
    | ($enriched | map(.id)) as $known_ids
    | ($counts | keys
        | map(select(. as $id | ($known_ids | index($id)) | not))
        # LOAD-BEARING: te-* prefix reserved for token-efficiency telemetry
        # (issue #3494, compound Phase 1.6). Removing this filter breaks the
        # aggregation run — every Phase 1.6 outlier would fail orphan-gate.
        # Tests T6/T7/T8 in scripts/rule-metrics-aggregate.test.sh cover this.
        # AGENTS.md section prefixes are hr|wg|cq|rf|pdr|cm; te- cannot collide.
        | map(select(startswith("te-") | not))
        # gdpr-gate-* prefix reserved for gdpr-gate skill telemetry
        # (gdpr-gate-staleness, gdpr-gate-touch, gdpr-gate-cron-binding —
        # the last introduced by PR #3541). These are operational events
        # tied to the skill, not rule_ids in the AGENTS.md taxonomy.
        | map(select(startswith("gdpr-gate-") | not))
        # context-reviewed-* prefix reserved for context-reviewed-gate.sh
        # telemetry (context-reviewed-gate deny, context-reviewed-hook-self-fault
        # warn — issue #5999, ADR-094). The freshness audit tripwire logs
        # undeclared last_reviewed bumps; these are operational events tied to
        # the hook, not rule_ids in the AGENTS.md taxonomy (the always-loaded
        # B_ALWAYS budget has no room for a new core tag).
        | map(select(startswith("context-reviewed-") | not))
        # Hook-canonical Pencil rule_ids: per cq-agents-md-tier-gate, the rule
        # body lives in the hook header + pencil-setup SKILL (a Pencil-domain
        # rule is tier-gated OUT of AGENTS.md), so they legitimately never appear
        # in $known_ids. cq-before-calling-mcp-pencil-open-document (retired,
        # pencil-open-guard.sh) and cq-pencil-collapse-auto-recover (#4859,
        # pencil-collapse-guard.sh) are emitted by their hooks by design.
        | map(select(
            . != "cq-before-calling-mcp-pencil-open-document"
            and . != "cq-pencil-collapse-auto-recover"))
        # net-issue-flow* reserved for the blocking net-issue-flow gate
        # (ship/scripts/net-issue-flow.sh + .claude/hooks/ship-net-issue-flow-gate.sh,
        # issue #6769). Same tier-gate rationale as context-reviewed-*: the rule
        # body lives in the gate script header + ship/SKILL.md, and the
        # always-loaded B_ALWAYS budget has no room for a new core tag.
        # cost-of-filing-* is the review-disposition telemetry from
        # review/SKILL.md; the disposition rides in the rule_id
        # (cost-of-filing-flip-inline / cost-of-filing-file) because this
        # aggregator keys every counter on rule_id and never reads .kind.
        | map(select(startswith("net-issue-flow") | not))
        | map(select(startswith("cost-of-filing-") | not))) as $orphan_ids
    | {
        schema: $schema,
        generated_at: $generated_at,
        rules: $enriched,
        summary: {
          total_rules_tagged: ($enriched | length),
          # first_seen may be null (rule exists in AGENTS.md, never emitted)
          # or a malformed timestamp string (crash-mid-write). try/catch
          # treats parse failure as epoch 0 — pushes the rule into "unused"
          # which matches intent: we can'"'"'t prove recent activity.
          rules_unused_over_8w: ($enriched
            | map(select(.fire_count == 0
                and (.first_seen == null
                     or (try (.first_seen | fromdateiso8601) catch 0) < $cutoff)))
            | length),
          rules_bypassed_over_baseline: ($enriched
            | map(select(.bypass_count > 0))
            | length),
          orphan_rule_ids: $orphan_ids,
          # Telemetry-drop sentinel counts (issue #3509). Per-class counts
          # default to 0 when the class has no occurrences. emit_incident
          # has no `flock_timeout` site (indefinite flock per plan-review),
          # so that field is intentionally absent for this sink.
          drops_jq_fail_count: ($drops["jq_fail"] // 0),
          drops_rotation_fail_count: ($drops["rotation_fail"] // 0)
        }
      }
  ')
echo "$report" | jq empty >/dev/null 2>&1 || { echo "ERROR: stage C (summarize) malformed" >&2; exit 4; }

# Schema field assertion — shape-gate so downstream consumers can trust the
# field is present without defensive `// null` in every reader.
echo "$report" | jq -e '.schema == 1' >/dev/null 2>&1 \
  || { echo "ERROR: rule-metrics output missing or wrong schema version" >&2; exit 4; }

# Orphan invariant: any rule_id emitted by a hook / skill that is not tagged
# in AGENTS.md indicates drift (renamed rule, typo in snippet, dead rule-id).
# The aggregation run surfaces this as a failing step — the next run is a
# silent normalization otherwise. The file IS still written first so
# operators have forensic context for the orphan list on failed runs.
orphan_count=$(echo "$report" | jq -r '.summary.orphan_rule_ids | length')

if [[ "$DRY_RUN" == "1" ]]; then
  echo "$report" | jq '{schema, generated_at, summary}'
  if [[ "${orphan_count:-0}" -gt 0 ]]; then
    orphan_list=$(echo "$report" | jq -r '.summary.orphan_rule_ids | join(", ")')
    echo "ERROR: orphan rule_id(s) in incidents jsonl not tagged in AGENTS.md: $orphan_list" >&2
    exit 5
  fi
  exit 0
fi

# --- No-op guard: zero rule-carrying incident lines (issue #6042) ----------
# When the merged incident stream has zero valid rule_id rows — an empty or
# absent .rule-incidents.jsonl (the fresh-checkout CI case) OR a sentinel-only
# log (non-empty, but zero rule_id rows) — do NOT write rule-metrics.json and
# do NOT rotate. A write here would clobber the committed real aggregate with an
# all-zero snapshot; the authoritative producer is the local compound flow where
# the log actually exists (ADR-091). Keyed on valid_lines (rule-carrying rows),
# NOT file size — a sentinel-only file is non-empty but carries zero rule_id
# rows, and that is the exact clobber this guard exists to prevent. The report
# build and --dry-run print above are intentionally left intact so compound's
# unused-rules hint (compound/SKILL.md step 8) still parses.
if [[ "${valid_lines:-0}" -eq 0 ]]; then
  echo "rule-metrics: 0 rule-carrying incident lines; leaving committed $OUT unchanged." >&2
  if [[ "${drops_total:-0}" -gt 0 ]]; then
    drops_breakdown=$(jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ")' <<< "$drops_counts_json" 2>/dev/null || echo "")
    echo "rule-metrics: filtered $drops_total telemetry-drop sentinel row(s) [${drops_breakdown}]; no aggregate written." >&2
  fi
  exit 0
fi

# --- Materially-changed write (R5 mitigation) -----------------------------
# Compare against existing file ignoring generated_at so cron Sunday runs
# don't produce diff-noise-only commits. `jq -S` sorts keys so ordering
# differences (e.g., a jq pipeline refactor that swaps two object fields)
# don't trigger a spurious rewrite.
write=1
if [[ -f "$OUT" ]]; then
  existing_body=$(jq -S 'del(.generated_at)' < "$OUT" 2>/dev/null || echo "")
  new_body=$(echo "$report" | jq -S 'del(.generated_at)')
  if [[ "$existing_body" == "$new_body" ]]; then
    write=0
  fi
fi

if [[ "$write" == "1" ]]; then
  echo "$report" > "$OUT.tmp"
  jq empty "$OUT.tmp" >/dev/null 2>&1 || { echo "ERROR: tmp file malformed" >&2; rm -f "$OUT.tmp"; exit 5; }
  mv "$OUT.tmp" "$OUT"
  echo "Wrote $OUT"
else
  echo "No material change to $OUT"
fi

# Orphan gate (post-write): fail loudly if the jsonl emitted rule_ids not
# present in AGENTS.md. File is already written so operators have forensic
# context; rotation below is skipped because the exit short-circuits. The
# workflow's notify-ops-email catches this via `if: failure()`.
if [[ "${orphan_count:-0}" -gt 0 ]]; then
  orphan_list=$(echo "$report" | jq -r '.summary.orphan_rule_ids | join(", ")')
  echo "ERROR: orphan rule_id(s) in incidents jsonl not tagged in AGENTS.md: $orphan_list" >&2
  exit 5
fi

# --- Rotate jsonl after a successful aggregation --------------------------
# Scope down: only rotate when we're in a real CI/aggregator run (not tests).
# Detection: the incidents file exists AND it's non-empty AND rotation was
# explicitly requested via env AGGREGATOR_ROTATE=1 (default off to keep
# tests deterministic).
#
# Flock re-entrancy: `flock -x 9 … 9>>"$INCIDENTS"` acquires the same
# file-backed lock that the hook-writer's emit_incident acquires. Both use
# `-x` (exclusive), both target the same inode — they queue behind each
# other. Moving to a different fd would create two separate locks on the
# same inode and reintroduce the rotate/write race.
if [[ "${AGGREGATOR_ROTATE:-0}" == "1" && -s "$INCIDENTS" ]]; then
  ts=$(date -u +%Y-%m)
  archive="$REPO_ROOT/.claude/.rule-incidents-${ts}.jsonl"
  # Uniquify BEFORE entering the flock subshell — subshell variable
  # assignments do not propagate back, so reassigning `archive` inside
  # would leave the outer gzip pointing at a non-existent basename.
  # An already-rotated `.gz` or a lingering uncompressed file from a
  # mid-run crash both count as "already exists" here; we append to a
  # fresh suffixed name rather than clobbering.
  # Suffix uses nanoseconds so two rotations within the same second (rare
  # in production, common in tests) do not re-collide. Tests may override
  # the suffix via RULE_METRICS_ROTATE_SUFFIX for deterministic paths.
  if [[ -f "${archive}.gz" || -f "$archive" ]]; then
    suffix="${RULE_METRICS_ROTATE_SUFFIX:-$(date -u +%H%M%S%N)}"
    archive="$REPO_ROOT/.claude/.rule-incidents-${ts}-${suffix}.jsonl"
  fi
  (
    flock -x 9
    cat "$INCIDENTS" >> "$archive"
    : > "$INCIDENTS"
  ) 9>>"$INCIDENTS"
  gzip -f "$archive" 2>/dev/null || true
  echo "Rotated $INCIDENTS to $archive.gz"
fi
