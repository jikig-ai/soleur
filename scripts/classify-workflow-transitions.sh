#!/usr/bin/env bash
# Report workflow transitions that the declared edge set does not permit.
#
# WHY THIS IS OFFLINE AND NOT A HOOK (#8302, ADR-229).
# The plan originally specified a record-mode PreToolUse hook on the Skill
# matcher. Plan review cut it on two independent grounds:
#
#   1. Its output would dead-end. A record-mode event carries no corpus rule-id
#      prefix, so scripts/rule-metrics-aggregate.sh files it under
#      summary.non_corpus_counts -- a bare integer that nothing reads -- and
#      compound's Deviation Analyst ingests only
#      event_type in {deny, bypass} or kind == "hook_self_fault",
#      none of which a record-mode gate can emit. It would have recorded forever
#      into a counter no surface displays.
#   2. The data already exists. .claude/hooks/skill-invocation-logger.sh appends
#      {ts, skill, session_id} on every Skill call. Only the
#      classification was missing, and classification does not need a hook --
#      which also means nothing new can wedge a session, and ADR-070's two-tier
#      rule (deny-by-default only on re-fetching layers) is not engaged at all.
#
# PROPERTY: for every session in the invocation log, each consecutive pair of
# LIFECYCLE-NODE records (non-node records removed first, so a sub-skill hop
# collapses to the transition it encloses; then a node record whose skill the
# view's `sub_steps` names as a designed sub-step of the PREVIOUS KEPT node is
# dropped and counted as `substep`, so `brainstorm compound plan` pairs as
# `brainstorm -> plan` -- #8325) whose edge is absent from the declared set is
# reported exactly once, attributed to its session.
#
# Usage:
#   scripts/classify-workflow-transitions.sh              # one row per violation
#   scripts/classify-workflow-transitions.sh --summary    # counts only
#
# CLASSIFY_REPO_ROOT is an EXCLUSIVE override: when set, only that root is read
# and sibling-worktree enumeration is skipped. Tests depend on that narrowing;
# never widen past it.
set -euo pipefail

SUMMARY=0
for arg in "$@"; do
  case "$arg" in
    --summary) SUMMARY=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: classify-workflow-transitions.sh [--summary]
  default    one TSV row per undeclared lifecycle transition: <session_id>\t<from> -> <to>
  --summary  one key=value line: undeclared= sessions= pairs= nonnode= substep= read= dropped= [null_reading=1]
             (substep = node records dropped as a designed sub-step of the previous kept node, per the view's sub_steps)
env: CLASSIFY_REPO_ROOT=<dir>  read ONLY that root (skips the main-checkout/sibling enumeration)
exit: 0 classified (a null reading still exits 0 and says so); 2 could not classify
USAGE
      exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/incidents-roots.sh
source "$SCRIPT_DIR/lib/incidents-roots.sh"

REPO_ROOT="${CLASSIFY_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VIEW="$REPO_ROOT/.claude/workflow-transitions.json"

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required (install jq, or run this where the aggregator runs)" >&2; exit 2; }

# FAIL CLOSED on a missing edge set. Classifying against an empty set would
# report EVERY transition as undeclared -- a confident wrong answer, which is
# worse than a missing one.
if [[ ! -r "$VIEW" ]]; then
  echo "FATAL: declared transition view not readable at $VIEW" >&2
  echo "       The view is repo tooling, not part of the shipped plugin (ADR-229): this probe" >&2
  echo "       runs only in a soleur source checkout. On such a checkout, restore it from git." >&2
  exit 2
fi
# FAIL CLOSED on a view without an OBJECT `transitions`. Readability was the
# only thing checked, so `del(.transitions)` or `.transitions = null` reported
# `undeclared=0 ... rc 0` -- a clean-looking zero over an empty edge set, which
# is the silent-zero this script exists to refuse. (`[]` already errored, which
# is how asymmetric the guard was.) Added #8325, alongside the `sub_steps` one
# below, because adding the second check is what made the first one's absence
# visible.
if ! jq -e '.transitions | type == "object"' "$VIEW" >/dev/null 2>&1; then
  echo "FATAL: declared view $VIEW carries no \`transitions\` object — stale or truncated mirror;" >&2
  echo "       classifying against an empty edge set would report every transition as undeclared." >&2
  exit 2
fi
# FAIL CLOSED on a view without an OBJECT `sub_steps` (#8325). A tolerant `// {}`
# would silently reproduce the pre-collapse numbers on a stale mirror, and
# `"sub_steps": null` or `[]` passes a bare has() check with the same silent
# result -- so the type is asserted, not the presence.
if ! jq -e '.sub_steps | type == "object"
            and all(.[]; type == "array" and all(.[]; type == "string"))' "$VIEW" >/dev/null 2>&1; then
  echo "FATAL: declared view $VIEW carries no \`sub_steps\` map of string arrays — stale mirror;" >&2
  echo "       (a STRING value would pass a container-only check and then collapse by SUBSTRING match)" >&2
  echo "       edit DECLARED_SUB_STEPS" >&2
  echo "       in plugins/soleur/lib/workflow-fidelity.ts first, then mirror it (ADR-229, amended #8325)." >&2
  exit 2
fi

# The invocation log has the SAME per-root fragmentation as the incident log --
# both resolve through the hook's own dirname -- so it gets the same treatment:
# enumerate sibling worktrees, then dedupe by inode so a root reachable by two
# different path strings is not walked twice.
# WHERE THE LOG IS. The Skill logger (.claude/hooks/skill-invocation-logger.sh)
# is registered via $CLAUDE_PROJECT_DIR and, measured 2026-09-18, every one of
# 10,290 live invocation records sat in the MAIN checkout's .claude -- zero in
# any sibling worktree. The incident log fragments per root; this one does not.
# But this script may run FROM a worktree, where $REPO_ROOT/.claude has no log:
# the review's simplification pass tried "one root" and got a NULL reading from
# exactly this worktree. The shared enumeration (repo root, main worktree,
# siblings, inode-deduped) is how the main checkout is reached from anywhere;
# the sibling entries are empty today and cost ~4 ms.
ROOTS=("$REPO_ROOT/.claude")
if [[ -z "${CLASSIFY_REPO_ROOT:-}" ]]; then
  _dd=()
  while IFS= read -r -d '' _d; do
    [[ -n "$_d" ]] || continue
    _dd+=("$_d")
  done < <(incidents_enumerate_log_roots "$REPO_ROOT")
  [[ ${#_dd[@]} -gt 0 ]] && ROOTS=("${_dd[@]}")
fi

MERGED=$(mktemp -t classifyinv.XXXXXXXX)
trap 'rm -f -- "$MERGED"' EXIT INT TERM

found=0
for d in "${ROOTS[@]}"; do
  if [[ -s "$d/.skill-invocations.jsonl" ]]; then
    if [[ -r "$d/.skill-invocations.jsonl" ]]; then
      cat "$d/.skill-invocations.jsonl" >> "$MERGED" || true
      found=1
    else
      echo "SOLEUR_WORKFLOW_TRANSITIONS_ROOT_UNREADABLE root=$d — enumerated but not readable; its records are ABSENT from this reading" >&2
    fi
  fi
  # ROTATED ARCHIVES. The producer rotates the live log through log-rotation.sh
  # into .skill-invocations-<ts>.jsonl.gz, and the aggregator's sibling readers
  # (skill-freshness-aggregate.sh, token-efficiency-report.sh) already zcat them.
  # Reading only the live file made a session split across a rotation boundary
  # (plan in the archive, ship in the live file) report pairs=1 undeclared=0 --
  # and the corpus, and the followthrough's baseline with it, would have shrunk
  # silently at every rotation. Found at review by two independent seats.
  # `-s` not `-f`, and `found=1` only once bytes actually landed: a 0-byte or
  # non-gzip archive used to set found=1 with nothing appended, so `read=0` fell
  # through every downstream guard and the run reported an empty report at rc 0
  # with NO null-reading marker -- the exact failure case 8 pins for the live
  # log, reachable through the archive limb the corpus was later widened to.
  for _gz in "$d"/.skill-invocations-*.jsonl.gz; do
    [[ -s "$_gz" ]] || continue
    _before=$(wc -c < "$MERGED" 2>/dev/null || echo 0)
    zcat -- "$_gz" >> "$MERGED" 2>/dev/null || true
    _after=$(wc -c < "$MERGED" 2>/dev/null || echo 0)
    [[ "$_after" -gt "$_before" ]] && found=1
  done
done

# Absence must be LOUD. A missing log and a log of genuinely zero violations
# both produce an empty report, and the silent one reads as an all-clear --
# the same null-reading trap the aggregator guards with
# SOLEUR_RULE_METRICS_NO_INCIDENTS.
if [[ "$found" -eq 0 ]]; then
  echo "SOLEUR_WORKFLOW_TRANSITIONS_NO_INVOCATIONS roots=${ROOTS[*]} reason=absent — this is a NULL reading, not an all-clear" >&2
  echo "       The producer is .claude/hooks/skill-invocation-logger.sh; its log is gitignored and exists only" >&2
  echo "       where sessions have run. A fresh checkout or CI runner has none, by construction." >&2
  # Same key set as the real summary line, plus an explicit flag -- one schema
  # per flag, so a key=value consumer never sees two shapes.
  [[ "$SUMMARY" -eq 1 ]] && echo "undeclared=0 sessions=0 pairs=0 nonnode=0 substep=0 read=0 dropped=0 null_reading=1"
  exit 0
fi

# Classification, in one jq pass:
#   - strip the `soleur:` namespace so skills match the edge set's node names
#   - group by session_id, because without it the "previous skill" is whatever
#     the last call of a DIFFERENT session was, which makes cross-session false
#     positives the dominant output rather than the exception
#   - sort within a session by timestamp, then walk consecutive pairs
#   - records whose skill is not a declared node (go, one-shot, deepen-plan,
#     preflight, qa, ...) are removed BEFORE pairing, so a sub-skill hop between
#     two lifecycle nodes collapses to the lifecycle transition it encloses.
#     Their count is surfaced as `nonnode` in --summary so the exclusion is
#     visible rather than silent.
#   - THEN (#8325) a node record whose skill is in sub_steps[<previous KEPT
#     node>] is dropped before pairing: brainstorm runs compound as its own
#     designed sub-step and hands off to plan, so `brainstorm compound plan` is
#     the designed handoff, not two undeclared edges. Keyed on the previous KEPT
#     record, so `brainstorm compound compound plan` drops both. The count is
#     surfaced as `substep`. Order is load-bearing: non-node removal first, so
#     `brainstorm one-shot compound plan` still collapses.
read -r -d '' JQ <<'JQEOF' || true
  # `-R` + `fromjson?`: one malformed line (a truncated tail in the live log or
  # any rotated archive) must count as DROPPED, not blank the whole reading.
  # `[inputs]` on parsed JSON aborted at the first bad byte with rc 2 and zero
  # rows -- loud, but the remedy was hand-editing a gitignored log. The
  # aggregator's per-line `fromjson?` precedent is what this follows.
  [inputs | fromjson?]
  # The producer's timestamp field is `ts` (skill-invocation-logger.sh), NOT
  # `timestamp`. Reading the generator's prose instead of a real record cost a
  # silent zero: filtering on `.timestamp` dropped all 10,260 live records and
  # reported "undeclared=0 pairs=0", which is indistinguishable from a clean
  # run. `dropped` below exists so that can never be silent again.
  #
  # `session_id != ""` as well as `!= null`: an empty string passes a null test
  # and would POOL every such record into one phantom session, fabricating pairs.
  | . as $raw
  | map(select((.skill | type) == "string" and (.session_id | type) == "string"
               and .session_id != "" and (.ts | type) == "string"))
  | map(.t = .ts)
  # ltrimstr, not sub(): identical for a prefix strip and ~35% cheaper at 10x
  # volume (regex compiled per record).
  | map(.skill |= ltrimstr("soleur:"))
  | $read_lines as $read
  | (length) as $kept
  # Bind the edge map BEFORE piping. `X | has(.from)` evaluates `.from` against
  # X, not against the element, because `|` rebinds `.` -- the same scoping trap
  # as `list | index(.key)`. It fails loudly ("Cannot check whether object has a
  # null key"), but the `index` variant would silently never match.
  | ($decl[0].transitions) as $T
  | ($decl[0].sub_steps) as $SUB
  # LIFECYCLE NODES ONLY, then pair. The first version paired RAW adjacent
  # records and required both endpoints to be nodes, which was correct about one
  # thing (ship -> preflight is not a lifecycle transition) and wrong about the
  # thing that matters: plan -> deepen-plan -> ship produced two unclassified
  # pairs and ZERO violations, so the review-skip was invisible on exactly the
  # most common real path (plan -> deepen-plan occurs 736 times in the corpus).
  # Filtering each session to node records first collapses the sub-skill hop
  # and pairs plan with ship, which the edge set then refuses. Two review seats
  # found this independently against the pristine script.
  | map(select(. as $r | $T | has($r.skill))) as $nodes
  | ($kept - ($nodes | length)) as $nonnode
  | $nodes
  | group_by(.session_id)
  | map(sort_by(.t))
  # SUB-STEP COLLAPSE, per session, after sorting and before pairing. The
  # first-record branch is not optional: `.kept[-1]` on an empty array is null
  # and `$SUB[null]` throws "Cannot index object with null", which `// []` does
  # not rescue (verified). Equal-second ties keep merged-file order (sort_by is
  # stable).
  | map(reduce .[] as $r ({kept: [], sub: 0};
          if (.kept | length) == 0 then .kept += [$r]
          elif (($SUB[.kept[-1].skill] // []) | index($r.skill)) != null then .sub += 1
          else .kept += [$r] end))
  | (map(.sub) | add // 0) as $substep
  | map(.kept)
  | map(. as $s | [range(1; ($s | length))]
        | map({ session: $s[0].session_id, from: $s[. - 1].skill, to: $s[.].skill }))
  | flatten
  | { read: $read,
      kept: $kept,
      dropped: ($read - $kept),
      nonnode: $nonnode,
      substep: $substep,
      pairs: length,
      sessions: (map(.session) | unique | length),
      violations: map(select(. as $p | ($T[$p.from] // []) | index($p.to) == null)) }
JQEOF

# `-n` so jq does not consume the first object implicitly; `[inputs]` then slurps
# the whole stream. Errors are NOT suppressed: an empty RESULT renders exactly
# like "no violations", so a parse failure must be loud rather than clean.
# `read` is the LINE count of the merged corpus, computed here, because after
# `fromjson?` jq can no longer see how many lines failed to parse.
read_lines=$(grep -c . "$MERGED" || true)
if ! RESULT=$(jq -n -R --slurpfile decl "$VIEW" --argjson read_lines "${read_lines:-0}" "$JQ" < "$MERGED"); then
  echo "FATAL: could not classify the merged invocation log (roots: ${ROOTS[*]}) against $VIEW" >&2
  exit 2
fi
if [[ -z "$RESULT" ]]; then
  echo "FATAL: classification produced no output (roots: ${ROOTS[*]}) — treating as unresolved, not clean" >&2
  exit 2
fi

n=$(printf '%s' "$RESULT" | jq -r '.violations | length')
pairs=$(printf '%s' "$RESULT" | jq -r '.pairs')
sessions=$(printf '%s' "$RESULT" | jq -r '.sessions')
nonnode=$(printf '%s' "$RESULT" | jq -r '.nonnode')
substep=$(printf '%s' "$RESULT" | jq -r '.substep')
read_n=$(printf '%s' "$RESULT" | jq -r '.read')
kept=$(printf '%s' "$RESULT" | jq -r '.kept')
dropped=$(printf '%s' "$RESULT" | jq -r '.dropped')

# A LOG THAT PARSES TO NOTHING IS NOT A CLEAN RUN. If records were read but none
# carried the expected shape, every downstream count is zero and reads exactly
# like "no violations" -- the failure this script hit on its own first live run,
# where a wrong timestamp field name discarded all 10,260 records behind
# "undeclared=0". Fail loudly rather than reporting a zero nobody can distinguish
# from a pass.
if [[ "$read_n" -gt 0 && "$kept" -eq 0 ]]; then
  echo "FATAL: read $read_n invocation line(s) and kept 0 — none parsed as JSON carrying skill + session_id + ts." >&2
  echo "       This is an UNPARSEABLE log, not an absence of violations. Check the producer's record shape" >&2
  echo "       (.claude/hooks/skill-invocation-logger.sh) against the filter in this script." >&2
  exit 2
fi
if [[ "$dropped" -gt 0 ]]; then
  echo "WARNING: dropped $dropped of $read_n invocation line(s): unparseable JSON or missing skill/session_id/ts." >&2
fi
# Records but no lifecycle pair (every session a single node invocation): a
# corpus the instrument cannot say anything about. Not dark, not clean -- say so.
if [[ "$kept" -gt 0 && "$pairs" -eq 0 ]]; then
  echo "WARNING: $kept record(s) formed ZERO lifecycle pairs; undeclared=0 here is an empty reading, not a clean one." >&2
fi

if [[ "$SUMMARY" -eq 1 ]]; then
  echo "undeclared=$n sessions=$sessions pairs=$pairs nonnode=$nonnode substep=$substep read=$read_n dropped=$dropped"
  exit 0
fi

# @tsv escapes tabs/newlines inside the fields, which come straight from the
# log's `skill`/`session_id` (unshaped by the producer); a raw interpolation let a
# crafted skill name forge extra rows and columns.
printf '%s' "$RESULT" | jq -r '.violations[] | [.session, (.from + " -> " + .to)] | @tsv | "  " + .'
exit 0
