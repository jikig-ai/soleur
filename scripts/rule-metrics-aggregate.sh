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

# --- Retired AGENTS.md rule ids -------------------------------------------
# Clause 2 of the orphan discriminator (see the summary stage below). Same file
# and same parse as scripts/rule-prune.sh `_load_retired_ids`: the id is column
# 1 of `<id> | <date> | <PR #> | <breadcrumb>`, comment and blank lines skipped.
# Read from $REPO_ROOT so a redirected root pairs its own AGENTS.md with its own
# retirement record — the same pairing $RULE_METRICS_ROOT gives rule-prune.sh.
# An absent file yields an empty list, which only makes the gate stricter.
RETIRED_IDS_SRC="$REPO_ROOT/scripts/retired-rule-ids.txt"
retired_ids_file="$_tmpdir/retired-ids.txt"
: > "$retired_ids_file"
if [[ -f "$RETIRED_IDS_SRC" ]]; then
  awk '/^[^#]/ {
    sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "")
    if ($0 == "") next
    split($0, a, "[ \t]*\\|[ \t]*")
    gsub(/[ \t]+/, "", a[1])
    if (a[1] != "") print a[1]
  }' "$RETIRED_IDS_SRC" > "$retired_ids_file"
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
  --argjson cutoff "$UNUSED_CUTOFF_EPOCH" \
  --rawfile retired_txt "$retired_ids_file" '
    ($enriched_json | fromjson) as $enriched
    | ($counts_json | fromjson) as $counts
    | ($retired_txt | split("\n") | map(select(length > 0))) as $retired_ids
    # Orphan events: rule_ids in the jsonl that match no AGENTS.md id.
    # Surfacing these prevents silent data loss when a hook emits a rule_id
    # that was renamed / removed / never tagged (e.g., historical sentinel names).
    #
    # THE DISCRIMINATOR (#7853). This gate used to carry NINE hand-maintained
    # exemption stanzas — te-, gdpr-gate-, context-reviewed-, net-issue-flow,
    # cost-of-filing-, grep-rewrite-, monitor-supersede, hook-input-, plus two
    # exact ids. Every one of them existed because the gate treated EVERY
    # emitted identifier as a claim to be an AGENTS.md rule, when most emitters
    # are hooks whose ids never claimed corpus membership at all. Each new hook
    # cost another stanza, and until someone wrote it the gate exited 5 and, on
    # the post-write path, short-circuited before jsonl rotation — so one hook
    # could disarm rotation of the shared telemetry sink.
    #
    # Two clauses replace all nine. An id is an orphan when it:
    #   1. CLAIMS CORPUS MEMBERSHIP — carries an AGENTS.md section prefix
    #      (hr|wg|cq|rf|pdr|cm). Measured 2026-09-07: 0 of 105 AGENTS ids lack
    #      one, so this clause cannot exempt a live corpus rule. Telemetry that
    #      never claimed to be a rule is now structurally out, which is what
    #      makes this gate stop needing maintenance; AND
    #   2. IS NOT DELIBERATELY RETIRED — absent from scripts/retired-rule-ids.txt.
    #      A retired rule whose emitter literal outlived it is telemetry
    #      legitimately outside the corpus; that is what retirement means. And
    #      cq-rule-ids-are-immutable makes reintroducing a retired id
    #      linter-rejected, so renaming such an emitter back into AGENTS.md is
    #      not an available repair.
    #
    # Anything surviving both clauses is a real orphan and still exits 5 —
    # verified non-vacuous by injecting a section-prefixed, non-retired id.
    #
    # LOAD-BEARING PAIR, preserved: hook-input-* (ADR-156/ADR-157) and
    # grep-rewrite-* (ADR-162) carry no section prefix, so clause 1 drops them
    # here exactly as their explicit stanzas did. That leaves orphan_rule_ids
    # as no surface at all for those counts-only ids, so
    # summary.hook_input_fault_count and summary.grep_rewrite_fault_count below
    # remain their replacement surfaces and must not be removed independently
    # of this filter. The same holds for the net-issue-flow* attribution
    # readouts (gate_exemptions and friends).
    | ($enriched | map(.id)) as $known_ids
    | ($counts | keys
        | map(select(. as $id | ($known_ids | index($id)) | not))
        | map(select(test("^(hr|wg|cq|rf|pdr|cm)-")))
        | map(select(. as $id | ($retired_ids | index($id)) | not))
        # The one residual exact exemption, and the only id in this corpus that
        # both clauses let through. cq-pencil-collapse-auto-recover (#4859,
        # .claude/hooks/pencil-collapse-guard.sh) is hook-canonical: per
        # cq-agents-md-tier-gate a Pencil-domain rule is tier-gated OUT of
        # AGENTS.md, so the rule body lives in the hook header plus the
        # pencil-setup SKILL and the id never appears in $known_ids. Unlike the
        # four other section-prefixed non-corpus ids measured in this ledger it
        # was never retired, because it was never IN AGENTS.md to retire, so
        # clause 2 does not reach it. The durable repair is to rename the
        # emitter literal to an unprefixed id, which the immutability rule does
        # permit for hook telemetry (it binds AGENTS.md [id: ...] tags only) —
        # that lives in the guard hook, outside this change.
        # NOTE: no apostrophes in this block. It is inside a single-quoted jq
        # program; one of them ends the program and bash parses the rest as shell.
        | map(select(. != "cq-pencil-collapse-auto-recover"))) as $orphan_ids
    # Hook input-contract faults, split out of $counts BEFORE the summary so the
    # count survives the orphan exclusion above. Keyed on rule_id like every
    # other counter in this script.
    | ($counts | to_entries
        | map(select(.key | startswith("hook-input-")))) as $hook_input_faults
    # grep-rewrite-* is hook self-fault telemetry — the SAME class as hook-input-*,
    # not the cost-of-filing-* disposition class an earlier draft cited. It means
    # "the rewriter broke", so the exclusion above needs the same replacement
    # readout the hook-input- exclusion documents as its LOAD-BEARING PAIR.
    # Without it the row appears in NO field of this report (measured).
    | ($counts | to_entries
        | map(select(.key | startswith("grep-rewrite-")))) as $grep_rewrite_faults
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
          # NB (#6794): a HIGH unused rate here is more likely a telemetry-
          # FRAGMENTATION artifact than dead weight — this aggregate reads only
          # ONE per-checkout .claude/.rule-incidents.jsonl, but events are split
          # across many worktrees. Do NOT treat this as a pruning mandate; read
          # knowledge-base/project/learnings/2026-07-22-rule-metrics-denominator-investigation.md
          # (union the logs + observe a real ≥8w window first) before any bulk prune.
          rules_unused_over_8w: ($enriched
            | map(select(.fire_count == 0
                and (.first_seen == null
                     or (try (.first_seen | fromdateiso8601) catch 0) < $cutoff)))
            | length),
          rules_bypassed_over_baseline: ($enriched
            | map(select(.bypass_count > 0))
            | length),
          orphan_rule_ids: $orphan_ids,
          # Gate-exemption readout (ADR-156). The net-issue-flow mandated-filing
          # exemption is justified by ATTRIBUTION — being able to see which rule
          # is being cited, how often, and whether the citing PRs look like
          # genuine mandates or a new reflex. That justification is only true if
          # the numbers are actually readable somewhere, and before this block
          # they were not: `net-issue-flow*` is filtered out of $orphan_rule_ids
          # a few lines up (correctly — those ids are tier-gated out of
          # AGENTS.md), and $enriched is built from AGENTS.md ids only, so the
          # rows reached this file NOWHERE. Shipping the framing without the
          # readout is the one thing this must not do.
          #
          # Keyed off the rule_id, not .kind: the emitter encodes the mandating
          # rule as `net-issue-flow-mandated-filing--<rule-id>` precisely so the
          # attribution is structured rather than buried in the free-text
          # rule_text_prefix that nothing parses.
          gate_exemptions: (
            [ $counts | to_entries[]
              | select(.key | startswith("net-issue-flow-mandated-filing--")) ]
            | map({
                rule: (.key | ltrimstr("net-issue-flow-mandated-filing--")),
                bypass_count: (.value.bypass_count // 0)
              })
            | sort_by(.rule)
          ),
          # The blanket override, counted separately. The comparison is the
          # signal worth watching: exemptions rising while overrides fall is the
          # intended effect; BOTH rising means the gate is being routed around
          # rather than satisfied.
          gate_override_count: (($counts["net-issue-flow"].bypass_count // 0)),
          # Distinct ids, deliberately. `net-issue-flow` + warn is the GENERIC
          # fail-open (gh outage, empty issue list); the timeout has its own id.
          # Sharing one id collapsed "the API was down" and "the gate was killed
          # for running too long" into a single number with two different fixes
          # — measured at 8 inseparable warns before the split.
          gate_timeout_warn_count: (($counts["net-issue-flow-timeout"].warn_count // 0)),
          gate_failopen_warn_count: (($counts["net-issue-flow"].warn_count // 0)),
          # These two were write-only until now: the single-dash ids that
          # correctly keep them OUT of gate_exemptions (which matches the
          # double-dash prefix) also kept them out of every other key, while
          # orphan_rule_ids filters the whole net-issue-flow prefix. So they
          # reached this file NOWHERE — consequence (b) of ADR-156 reproduced
          # one level down, in the PR that diagnosed it. They are distinct
          # conditions: "could not read the corpus" vs "read it, nothing tagged".
          # The second is expected rollout noise and should decay to 0; the
          # first should always be 0.
          # #7759. Same write-only trap as the two below, and named here for the
          # same reason: orphan_rule_ids filters the whole `net-issue-flow`
          # prefix, so a new id under it reaches this file through NO other key.
          # They answer two different questions and must not be merged:
          # `body_attributed` counts runs where a filing was countable ONLY
          # because the PR declared it — i.e. how often the pre-#7759 gate would
          # have under-counted — and should be non-zero if the fix is load-bearing.
          # `undelivered_declaration` counts runs where the PR declared a number
          # the gate could NOT match to an issue in range. It replaces an earlier
          # `unattributed_reported` field which counted every issue number a body
          # happened to mention: that set never joined the issue array, so it had
          # no recency filter and no exclusion of rows already counted, it fired
          # on ~87% of PRs, and it therefore sat at ceiling and could not rise
          # informatively. This one is bounded by what the PR actually declared.
          # `contradictory_declaration` counts runs where a number appeared on
          # BOTH the Filed: line and a close keyword; it should be 0.
          gate_body_attributed_count:
            (($counts["net-issue-flow-body-attributed"].applied_count // 0)),
          gate_undelivered_declaration_count:
            (($counts["net-issue-flow-undelivered-declaration"].warn_count // 0)),
          gate_contradictory_declaration_count:
            (($counts["net-issue-flow-contradictory-declaration"].warn_count // 0)),
          gate_unbalanced_fence_count:
            (($counts["net-issue-flow-unbalanced-fence"].deny_count // 0)),
          gate_corpus_unreadable_warn_count:
            (($counts["net-issue-flow-mandated-filing-corpus-unreadable"].warn_count // 0)),
          gate_zero_tagged_warn_count:
            (($counts["net-issue-flow-mandated-filing-zero-tagged"].warn_count // 0)),
          # Telemetry-drop sentinel counts (issue #3509). Per-class counts
          # default to 0 when the class has no occurrences. emit_incident
          # has no `flock_timeout` site (indefinite flock per plan-review),
          # so that field is intentionally absent for this sink.
          drops_jq_fail_count: ($drops["jq_fail"] // 0),
          drops_rotation_fail_count: ($drops["rotation_fail"] // 0),
          # Hook input-contract faults (issue #7164). A PreToolUse hook that
          # cannot fully parse its stdin emits `ask` in-band AND a row here.
          # Zero is healthy. Non-zero means at least one hook ran with its
          # guards disarmed for one tool call — see .claude/hooks/README.md
          # "Parsing hook input". This counter is the surface that replaces the
          # orphan_rule_ids listing removed by the exclusion above; the stderr
          # line below is what makes it visible without reading the JSON.
          grep_rewrite_fault_count: ($grep_rewrite_faults | map(.value.fire_count) | add // 0),
          grep_rewrite_fault_reasons: ($grep_rewrite_faults
            | map({key: (.key | ltrimstr("grep-rewrite-")), value: .value.fire_count})
            | from_entries),
          hook_input_fault_count: ($hook_input_faults | map(.value.fire_count) | add // 0),
          hook_input_fault_reasons: ($hook_input_faults
            | map({key: (.key | ltrimstr("hook-input-")), value: .value.fire_count})
            | from_entries)
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

# Hook input-contract faults (issue #7164). Mirrors the drops_* sentinel line
# above: the count is invisible to an operator who does not read the JSON, and
# the orphan-gate exclusion that keeps these rule_ids from failing the run also
# removed the only place they used to appear. Printed BEFORE the DRY_RUN branch
# so both the dry-run and the write path surface it. Advisory, never fatal — a
# disarmed hook is already reported in-band by a permissionDecision=ask.
hook_input_fault_count=$(echo "$report" | jq -r '.summary.hook_input_fault_count // 0')
grep_rewrite_fault_count=$(echo "$report" | jq -r '.summary.grep_rewrite_fault_count // 0')
if [[ "${grep_rewrite_fault_count:-0}" -gt 0 ]]; then
  grep_rewrite_breakdown=$(echo "$report" \
    | jq -r '.summary.grep_rewrite_fault_reasons | to_entries | map("\(.key)=\(.value)") | join(" ")' 2>/dev/null || echo "")
  echo "WARNING: $grep_rewrite_fault_count grep-rewrite event(s) [${grep_rewrite_breakdown}] — the ugrep shim was NOT neutralized for those calls (disarm = envelope unbuildable; would-rewrite = observe-only mode is ON, which disables the rewrite repo-wide). See ADR-162." >&2
fi

if [[ "${hook_input_fault_count:-0}" -gt 0 ]]; then
  hook_input_breakdown=$(echo "$report" \
    | jq -r '.summary.hook_input_fault_reasons | to_entries | map("\(.key)=\(.value)") | join(" ")' 2>/dev/null || echo "")
  echo "WARNING: $hook_input_fault_count PreToolUse hook input-contract fault(s) — a hook could not parse its stdin and ran with guards disarmed [${hook_input_breakdown}]. See .claude/hooks/README.md 'Parsing hook input' (ADR-157)." >&2
fi

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
