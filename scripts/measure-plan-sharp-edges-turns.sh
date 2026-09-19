#!/usr/bin/env bash
# Measure how many assistant TURNS elapse between a `soleur:plan` invocation and
# the first Read of the extracted Sharp Edges catalogue, over the operator's
# local Claude Code transcripts. #8325 §3, ADR-229.
#
# WHY. The plan skill's Sharp Edges section (~58k tokens) was extracted into
# `references/plan-sharp-edges.md` behind an unconditional late step on a
# per-TURN argument: a block loaded at turn 0 is re-sent on every turn of the
# run, one loaded at turn k is re-sent on none of the k turns before it, so the
# saving is ~58k x k cache-read tokens per run. k was unmeasured. This script
# measures it, offline, from the transcripts the harness already writes.
#
# WHAT IT NEVER DOES (ADR-179 d4; the transcripts are operator-private):
#   - it lives under scripts/, never under plugins/ (nothing ships);
#   - it makes no network call and writes nothing to disk;
#   - the parser READS more text than anything else here -- `k_ac` inspects
#     tool_use `content`/`new_string` bodies -- so every field it touches is
#     reduced to a boolean or an ordinal before it leaves jq;
#   - stdout carries numbers, `na`, fixed key names, the `#` header and the kind
#     tokens only; stderr carries the slug (HOME-masked) and counts only. No
#     message text, command, file content or transcript path is ever printed --
#     every external command's stderr is redirected, a jq program error counts
#     the whole file as dropped, and xtrace is switched off first thing so an
#     inherited SHELLOPTS cannot trace a path.
#
# HOW A RUN IS READ.
#   turn     = one API turn: assistant records grouped by `.requestId // .uuid`
#              in FIRST-SEEN order (one turn is split across several records,
#              one per content block); `isApiErrorMessage` records are not turns.
#   run      = (a) a turn carrying a Skill tool_use with input.skill ==
#              "soleur:plan" (several such blocks in one turn = one run), or
#              (b) a user record whose text STARTS with <command-message> and
#              carries <command-name>/soleur:plan</command-name> (operator-typed;
#              a tool_result or a prompt quoting the literal is not one), whose
#              start ordinal is the next assistant turn's ordinal minus one, so
#              k counts the same thing in both forms.
#   window   = the run's turns, up to the next run start in the same file or EOF.
#   preamble = the user record(s) delivered between the invocation and the next
#              assistant turn whose text block STARTS with `Base directory for
#              this skill` -- the skill body the harness actually loaded.
#              `extracted` iff that block names references/plan-sharp-edges.md.
#              Both discriminators anchor on the START of a text block: a
#              research agent's prompt that quotes a plan discussing these
#              literals carries them mid-text (measured: 21 phantom runs). This, not a merge
#              timestamp, discriminates post- from pre-extraction runs: 5 of 7
#              runs invoked after the merge had loaded a stale pre-extraction
#              body from an old plugin checkout.
#   k        = ordinal of the first Read whose file_path ends with
#              skills/plan/references/plan-sharp-edges.md (suffix: the installed
#              plugin loads from ~/.claude/plugins/cache/... with no
#              plugins/soleur/ prefix) minus the start ordinal; 0 is legal
#              (same turn, parallel tool call); -1 absent. Reported for
#              extracted runs only.
#   k_first  = first turn touching a knowledge-base/project/plans/ path via
#              Read/Write/Edit file_path or a Bash command (the brief's k';
#              since ADR-176 the skeleton write lands early, so this measures
#              turns-to-skeleton).
#   k_ac     = first Write/Edit to such a path whose content carries
#              `## Acceptance Criteria` -- the faithful pre-extraction stand-in
#              for "turns before the Sharp Edges pass".
#   kind     = post (extracted, Read found) | post_skipped (extracted, none) |
#              pre (not extracted) | unknown (no preamble record; counted,
#              excluded from every statistic).
set +x
set -euo pipefail

# Re-measure when plan-sharp-edges.md changes size: `saving_tokens_per_run` is
# CATALOGUE_TOKENS x median_k, so a stale constant drifts silently and still
# reads as measured.
CATALOGUE_TOKENS=58000 # ADR-229, measured 2026-09-18 (the harness's own count)
CATALOGUE_SUFFIX='skills/plan/references/plan-sharp-edges.md'

ROWS=0
for arg in "$@"; do
  case "$arg" in
    --rows) ROWS=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: measure-plan-sharp-edges-turns.sh [--rows]
  default  one key=value line, keys in this order (the order IS the contract; the null line uses the same order):
           runs= post= post_skipped= pre= unknown=                       (runs by kind)
           median_k= p10_k= p90_k= saving_tokens_per_run=               (post runs only; na when post=0)
           median_k_first= n_k_first= median_k_ac= n_k_ac=              (pre runs; -1 in rows means absent)
           window_from= window_to= files= parsed= dropped= [null_reading=1]
  --rows   before the summary, a header line '# kind<TAB>k<TAB>k_first<TAB>k_ac<TAB>turns_in_window' then one TSV row per run
env: MEASURE_TRANSCRIPT_ROOT=<dir>  EXCLUSIVE override: read ONLY that tree, skip slug derivation; tests depend on that narrowing, never widen past it
     MEASURE_PROJECT_PATH=<path>    derive the slug from this path instead of the checkout's common dir (only ever slugified, never opened)
exit: 0 measured (a null reading exits 0 and prints null_reading=1); 2 could not measure (jq missing, unreadable root)
USAGE
      exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }

# Claude Code's project slug: every non-alphanumeric character becomes `-`
# (`/.worktrees/` -> `--worktrees-`). A parameter expansion, not `tr -c`, which
# would append the newline as a trailing `-`. The rule collides (`/a-b` and
# `/a_b` both slug to `a-b`); that is the harness's rule, not something to fix.
slugify() { local p=$1; printf '%s' "${p//[^A-Za-z0-9]/-}"; }

# --- corpus -------------------------------------------------------------------
ROOTS=()
SLUG_LABEL=override
if [[ -n "${MEASURE_TRANSCRIPT_ROOT:-}" ]]; then
  [[ -d "$MEASURE_TRANSCRIPT_ROOT" && -r "$MEASURE_TRANSCRIPT_ROOT" ]] \
    || { echo "FATAL: MEASURE_TRANSCRIPT_ROOT is not a readable directory" >&2; exit 2; }
  ROOTS=("$MEASURE_TRANSCRIPT_ROOT")
else
  [[ -n "${HOME:-}" ]] || { echo "FATAL: HOME is unset; cannot locate the transcript tree" >&2; exit 2; }
  if [[ -n "${MEASURE_PROJECT_PATH:-}" ]]; then
    main_path=$MEASURE_PROJECT_PATH
  else
    # The common dir's parent is the MAIN checkout even from a worktree
    # (--show-toplevel would give the worktree, whose slug is a different and
    # much smaller corpus). Anchored on the script's own directory, never $PWD.
    common=$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      || { echo "FATAL: not inside a git checkout and MEASURE_PROJECT_PATH is unset" >&2; exit 2; }
    main_path=$(dirname "$common")
  fi
  slug=$(slugify "$main_path")
  home_slug=$(slugify "$HOME")
  SLUG_LABEL="${slug/#$home_slug/HOME}"
  projects="$HOME/.claude/projects"
  add_root() { local d; for d in "${ROOTS[@]+"${ROOTS[@]}"}"; do [[ "$d" == "$1" ]] && return 0; done; [[ -d "$1" && -r "$1" ]] && ROOTS+=("$1"); return 0; }
  add_root "$projects/$slug"
  # Live worktrees, wherever they live (a worktree-launched session gets its own slug).
  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] || continue
    add_root "$projects/$(slugify "${line#worktree }")"
  done < <(git -C "$SCRIPT_DIR" worktree list --porcelain 2>/dev/null || true)
  # Transcripts of worktrees that cleanup-merged already deleted. An exact
  # `<slug>--worktrees-*` name, never `<slug>*` (a sibling project whose path
  # starts with the slug would be pulled in), and `find`, never a bare glob (an
  # unmatched glob would hand the literal pattern on under set -e).
  if [[ -d "$projects" ]]; then
    while IFS= read -r -d '' d; do add_root "$d"; done \
      < <(find -- "$projects" -maxdepth 1 -type d -name "$slug--worktrees-*" -print0 2>/dev/null || true)
  fi
fi

# Every *.jsonl under the roots (top-level sessions AND <session>/subagents/):
# the one-shot planning phase runs `plan` inside an Agent, and 20 of 25 local
# plan runs lived in subagent transcripts. Symlinks are skipped and uncounted.
FILES=()
for r in "${ROOTS[@]+"${ROOTS[@]}"}"; do
  while IFS= read -r -d '' f; do FILES+=("$f"); done \
    < <(find -P -- "$r" -type f -name '*.jsonl' -print0 2>/dev/null || true)
done
files=${#FILES[@]}

null_line() {
  echo "runs=0 post=0 post_skipped=0 pre=0 unknown=0 median_k=na p10_k=na p90_k=na saving_tokens_per_run=na median_k_first=na n_k_first=0 median_k_ac=na n_k_ac=0 window_from=na window_to=na files=$files parsed=${1:-0} dropped=${2:-0} null_reading=1"
}
null_reading() { # reason parsed dropped
  echo "SOLEUR_PLAN_SHARP_EDGES_NO_PLAN_RUNS slug=$SLUG_LABEL files=$files reason=$1 — set MEASURE_TRANSCRIPT_ROOT=<dir> to point at a transcript tree, or MEASURE_PROJECT_PATH=<path> if the slug is wrong" >&2
  [[ "$ROWS" -eq 1 ]] && printf '# kind\tk\tk_first\tk_ac\tturns_in_window\n'
  null_line "${2:-0}" "${3:-0}"
  exit 0
}
[[ "$files" -gt 0 ]] || null_reading no_files

# Pre-filter in ONE process: a file with no `soleur:plan` bytes cannot hold a
# run. This is a CORRECTNESS filter, not an optimisation -- measured on the live
# corpus it removes 6 of 919 files (0.65%), because the available-skills listing
# in every system prompt carries the literal. Survivors are a superset
# (`soleur:plan-review`, quoted prose) costing one parse each.
# `-a` so an embedded NUL cannot flip grep into binary mode; `-Z` keeps the
# path list NUL-framed and in the pipe, never on stdout.
SURVIVORS=()
while IFS= read -r -d '' f; do SURVIVORS+=("$f"); done \
  < <(printf '%s\0' "${FILES[@]}" | xargs -0 -r grep -laFZ -- 'soleur:plan' 2>/dev/null || true)

# --- per-file parse -----------------------------------------------------------
# One jq invocation per survivor so a window ends at EOF of its OWN file. The
# program is fed by stdin only: no transcript value ever reaches --arg. The
# array constructor PROJECTS each record to the fields below before
# accumulating (measured <= 10% of whole-record RSS at the same wall time).
# Every projection is type-guarded: a string-typed `message` or `input` must
# not raise, because a jq error carries the offending VALUE.
read -r -d '' JQ <<'JQEOF' || true
  def str: if type == "string" then . else "" end;
  def obj: if type == "object" then . else {} end;
  def blocks: (.message | obj | .content) as $c
    | if ($c | type) == "array" then [$c[] | obj] else [] end;
  # A user record's TEXT blocks only (string content counts as one block);
  # tool_result content never does -- a Read of a document quoting the harness
  # literals must not read as the harness. Reduced to three booleans at once so
  # no text survives past the projection.
  def text_blocks: (.message | obj | .content) as $c
    | if ($c | type) == "string" then [$c]
      elif ($c | type) == "array" then [ $c[] | obj | select(.type == "text") | (.text | str) ]
      else [] end;
  [ inputs ] as $lines
  | [ $lines[] | fromjson? | select(type == "object")
    | if (.type == "assistant" or .type == "user") then
      { type,
        id: ((.requestId // .uuid) | tostring),
        err: (.isApiErrorMessage == true),
        ts: (.timestamp | str),
        tools: (if .type == "assistant"
                then [ blocks[] | select(.type == "tool_use")
                       | { name: (.name | str), input: (.input | obj) } ]
                else [] end),
        cmd: (.type == "user" and any(text_blocks[];
               startswith("<command-message>") and contains("<command-name>/soleur:plan</command-name>"))),
        preamble: (.type == "user" and any(text_blocks[]; startswith("Base directory for this skill"))),
        names_cat: (.type == "user" and any(text_blocks[];
               startswith("Base directory for this skill") and contains("references/plan-sharp-edges.md"))) }
      else { skip: true } end ] as $all
  | ($all | length) as $parsed
  | [ $all[] | select(.skip | not) ] as $recs
  # Ordered reduce, never group_by (which sorts by key and destroys turn order).
  # A user record remembers how many turns had started before it (`pos`).
  | reduce $recs[] as $r ({order: [], turns: {}, users: []};
      if $r.type == "assistant" then
        if $r.err then .
        elif .turns[$r.id] then .turns[$r.id].tools += $r.tools
        else .order += [$r.id] | .turns[$r.id] = {ord: (.order | length), ts: $r.ts, tools: $r.tools} end
      else .users += [{pos: (.order | length), ts: $r.ts, cmd: $r.cmd, preamble: $r.preamble, names_cat: $r.names_cat}] end)
  | (.order | length) as $N
  | [ .order[] as $id | .turns[$id] ] as $turns
  | .users as $users
  | ( [ $turns[] | select(any(.tools[]; .name == "Skill" and (.input.skill | str) == "soleur:plan"))
        | {s: .ord, form: "a", ts: .ts} ]
    + [ $users[] | select(.cmd) | {s: .pos, form: "b", ts: .ts} ] ) | sort_by(.s, .form) as $runs
  | def has_read($t): any($t.tools[]; .name == "Read" and ((.input.file_path | str) | endswith($cat)));
    def has_plans($t): any($t.tools[];
        ((.name == "Read" or .name == "Write" or .name == "Edit") and ((.input.file_path | str) | contains($plans)))
        or (.name == "Bash" and ((.input.command | str) | contains($plans))));
    def has_ac($t): any($t.tools[];
        (.name == "Write" or .name == "Edit") and ((.input.file_path | str) | contains($plans))
        and (((.input.content | str) + (.input.new_string | str)) | contains("## Acceptance Criteria")));
    def first_ord($ts; f): ([ $ts[] | select(f) | .ord ] | if length > 0 then .[0] else null end);
    { parsed: $parsed,
      lines: ($lines | length),
      runs: [ range(0; ($runs | length)) as $i
        | $runs[$i] as $run
        | (if $i + 1 < ($runs | length)
           then (if $runs[$i + 1].form == "a" then $runs[$i + 1].s else $runs[$i + 1].s + 1 end)
           else $N + 1 end) as $e
        | (if $run.form == "a" then $run.s else $run.s + 1 end) as $lo
        | [ $turns[] | select(.ord >= $lo and .ord < $e) ] as $w
        | [ $users[] | select(.pos == $run.s and .preamble) ] as $pre
        | (($pre | length) > 0) as $known
        | ($known and any($pre[]; .names_cat)) as $extracted
        | (first_ord($w; has_read(.))) as $rk
        | { kind: (if ($known | not) then "unknown"
                   elif $extracted and $rk != null then "post"
                   elif $extracted then "post_skipped"
                   else "pre" end),
            k: (if $extracted and $rk != null then $rk - $run.s else -1 end),
            k_first: ((first_ord($w; has_plans(.))) as $o | if $o == null then -1 else $o - $run.s end),
            k_ac: ((first_ord($w; has_ac(.))) as $o | if $o == null then -1 else $o - $run.s end),
            tiw: ([($e - $run.s - 1), 0] | max),
            # Only a date-shaped prefix ever leaves this program.
            date: (if ($run.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}")) then $run.ts[0:10] else "na" end) } ] }
JQEOF

# `lines` and `parsed` come from the SAME read inside jq. Counting lines with a
# separate `grep -c` was a RACE: a transcript appended to between the two reads
# made `parsed > read_lines`, so `dropped` went NEGATIVE (measured -9) and that
# negative contribution silently cancelled a genuinely unparseable file
# elsewhere in the corpus -- which matters because `dropped=0` is the
# parse-integrity signal this reading is quoted with. A file jq cannot read at
# all yields no rows, so it is visible as a survivor that contributed nothing
# rather than as a fabricated drop count.
ALL_ROWS=()
parsed=0
dropped=0
for f in "${SURVIVORS[@]+"${SURVIVORS[@]}"}"; do
  if out=$(jq -c -n -R --arg cat "$CATALOGUE_SUFFIX" --arg plans 'knowledge-base/project/plans/' "$JQ" < "$f" 2>/dev/null) \
     && [[ -n "$out" ]]; then
    ALL_ROWS+=("$out")
  fi
done
# One join, never `ALL+=` per file: that is quadratic (~450 MB of hidden memcpy
# at today's ~900 survivors, and the corpus grows with `cleanupPeriodDays`).
ALL=''
if [[ ${#ALL_ROWS[@]} -gt 0 ]]; then
  ALL=$(printf '%s\n' "${ALL_ROWS[@]}")
  read -r parsed dropped < <(printf '%s' "$ALL" | jq -s -r \
    '([.[] | .parsed] | add // 0) as $p | ([.[] | .lines] | add // 0) as $l
     | "\($p) \($l - $p)"' 2>/dev/null || echo "0 0")
fi
parsed=${parsed:-0}; dropped=${dropped:-0}

# --- summary ------------------------------------------------------------------
read -r -d '' SUMJQ <<'SUMEOF' || true
  def fmt: if . == floor then tostring else ((. * 10 | round) / 10 | tostring) end;
  def median: sort | length as $n
    | if $n == 0 then null elif ($n % 2) == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
  def rank($p): sort | length as $n | if $n == 0 then null else .[(($p * $n) | ceil) - 1] end;
  def na: if . == null then "na" else fmt end;
  [ .[] | .runs[] ] as $runs
  | [ $runs[] | select(.kind == "post") | .k ] as $ks
  | [ $runs[] | select(.kind == "pre" and .k_first >= 0) | .k_first ] as $kf
  | [ $runs[] | select(.kind == "pre" and .k_ac >= 0) | .k_ac ] as $ka
  | [ $runs[] | .date | select(. != "na") ] | sort as $dates
  | ($ks | median) as $mk
  | { runs: ($runs | length),
      post: ([ $runs[] | select(.kind == "post") ] | length),
      post_skipped: ([ $runs[] | select(.kind == "post_skipped") ] | length),
      pre: ([ $runs[] | select(.kind == "pre") ] | length),
      unknown: ([ $runs[] | select(.kind == "unknown") ] | length),
      median_k: ($mk | na), p10_k: ($ks | rank(0.1) | na), p90_k: ($ks | rank(0.9) | na),
      saving: (if $mk == null then "na" else ($mk * $tok) | fmt end),
      median_k_first: ($kf | median | na), n_k_first: ($kf | length),
      median_k_ac: ($ka | median | na), n_k_ac: ($ka | length),
      window_from: (if ($dates | length) > 0 then $dates[0] else "na" end),
      window_to: (if ($dates | length) > 0 then $dates[-1] else "na" end),
      rows: [ $runs[] | [.kind, .k, .k_first, .k_ac, .tiw] | map(tostring) | join("\t") ] }
  | (if $rows == 1 then "# kind\tk\tk_first\tk_ac\tturns_in_window\n" + (.rows | map(. + "\n") | join("")) else "" end)
    + "runs=\(.runs) post=\(.post) post_skipped=\(.post_skipped) pre=\(.pre) unknown=\(.unknown) median_k=\(.median_k) p10_k=\(.p10_k) p90_k=\(.p90_k) saving_tokens_per_run=\(.saving) median_k_first=\(.median_k_first) n_k_first=\(.n_k_first) median_k_ac=\(.median_k_ac) n_k_ac=\(.n_k_ac) window_from=\(.window_from) window_to=\(.window_to)"
    + " files=\($files) parsed=\($parsed) dropped=\($dropped)"
    + " unknown_count=\(.unknown)"
SUMEOF

runs_total=$(printf '%s' "$ALL" | jq -s '[ .[] | .runs | length ] | add // 0' 2>/dev/null || echo 0)
[[ "${runs_total:-0}" -gt 0 ]] || null_reading no_runs "$parsed" "$dropped"

result=$(printf '%s' "$ALL" | jq -s -r --argjson rows "$ROWS" --argjson tok "$CATALOGUE_TOKENS" \
           --argjson files "$files" --argjson parsed "$parsed" --argjson dropped "$dropped" "$SUMJQ" 2>/dev/null) \
  || { echo "FATAL: could not summarise the parsed runs" >&2; exit 2; }
# The trailing unknown_count token is a carrier for the stderr warning only;
# the printed line is the contract's key set.
unknown=${result##* unknown_count=}
printf '%s\n' "${result% unknown_count=*}"
if [[ "${unknown:-0}" -gt 0 ]]; then
  echo "WARNING: unknown=$unknown run(s) had no skill-body record between the invocation and the next assistant turn" >&2
fi
exit 0
