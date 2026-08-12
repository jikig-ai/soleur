#!/usr/bin/env bash
#
# (#7506) Regression suite for .github/workflows/follow-through-closure-guard.yml.
#
# THIS SUITE EXECUTES THE SHIPPED STEP BODY. It does not grep it.
#
# The property is "the step runs to completion and invokes `gh issue reopen` exactly once
# when a required field is missing". That quantifies over the WHOLE body: any shell abort
# above the reopen has the same effect as deleting the reopen, and a grep pins spelling
# rather than behaviour — the asserted line could sit in an unreached branch. The defect that
# motivated this suite was exactly that shape: two `printf` calls whose format begins with `-`
# and which lack the `--` guard, so bash parsed the format as options, printf exited 2, and
# `bash -e` killed the step BEFORE `gh issue reopen`. The workflow went red and the issue
# stayed closed — the precise inverse of the design, whose own comment says the reopen is the
# signal and the workflow should stay green.
#
# THE HARNESS IS `bash -e`, AND THAT IS A MEASURED CLAIM, NOT A STYLE CHOICE.
# `scripts/lint-workflow-errexit-capture.py` records that a `run:` block declaring no `shell:`
# key is invoked as `/usr/bin/bash -e {0}`, and that `shell: bash` is what maps to
# `--noprofile --norc -eo pipefail`. This step declares no `shell:` key (asserted by C11), so
# `bash -e` is faithful. Measured across four invocations of the UNFIXED file:
#
#   bash -e                                  rc=2   reopens=0   <- what Actions runs
#   bash --noprofile --norc -eo pipefail     rc=2   reopens=0
#   bash -e, with `--` added                 rc=0   reopens=1
#   plain bash (no -e)                       rc=0   reopens=1   <- defect INVISIBLE
#
# The last row is why the harness must carry `-e`: without it every other arm here is vacuous.
#
# THE BODY RUNS AS A CHILD PROCESS, NEVER SOURCED. It registers its own `trap ... EXIT` (which
# would clobber this suite's) and `exit 0`s on the complete-comment path (which would end the
# suite early with rc=0 — a vacuous PASS the floor cannot catch, because the floor line would
# never run).
#
# THE `gh` STUB EVALUATES THE BODY'S REAL `--jq` EXPRESSION THROUGH REAL `jq`, and emulates
# pagination. A stub returning canned JSON would make `comment_body` a serialized array in
# which every `grep -Fq` matches, so the comment SELECTOR — half of what this change fixes —
# would never be exercised and C5-C9 would all pass vacuously.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
WF="${ROOT}/.github/workflows/follow-through-closure-guard.yml"
STEP_NAME="Check closing comment for required fields"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
# COLUMN-0 AND `FAIL`-SHAPED so the nested-runner failure-marker regex selects it, and it
# names WHICH arm failed rather than only that something did.
fail() {
  fails=$((fails + 1))
  printf 'FAIL: %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '      rc=%s\n' "$2"
  [[ -n "${3:-}" ]] && printf '      out=%s\n' "${3:0:1200}"
  return 0
}

printf '\n=== follow-through-closure-guard ===\n\n'

[[ -f "$WF" ]] || { printf 'FAIL: workflow not found at %s\n' "$WF"; exit 1; }

# HARD-EXIT 2 WITHOUT PyYAML rather than degrading to a grep. A suite that silently swaps its
# extraction for a weaker one reports the same green while testing something else.
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step body (python3 -c "import yaml" failed)\n'
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: jq is required — the gh stub evaluates the body real --jq expression\n'
  exit 2
}

# ADR-129 rule (c): every allocation this suite makes is reclaimed by ONE handler.
TMP="$(mktemp -d -t ftcg.XXXXXXXX)" || { printf 'FAIL: mktemp failed\n'; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ── Extract the step body, and assert the premises the harness rests on ────────────
#
# Cardinality first: a renamed step must fire a loud failure rather than silently testing an
# empty body and reporting green.
python3 - "$WF" "$STEP_NAME" "$TMP" <<'PY'
import sys, yaml, json, re, pathlib
wf, want, tmp = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
d = yaml.safe_load(open(wf))
hits = [s for j in d["jobs"].values() for s in j.get("steps", []) if s.get("name", "") == want]
meta = {"count": len(hits)}
if len(hits) == 1:
    s = hits[0]
    body = s.get("run", "")
    env = s.get("env", {}) or {}
    meta["has_shell"] = "shell" in s
    meta["has_expr"] = "${{" in body
    # Every UPPERCASE $VAR the body READS must be declared in the step's env:. Lowercase
    # names are the body's own locals and are out of scope.
    read = set(re.findall(r'\$\{?([A-Z_][A-Z0-9_]*)\}?', body))
    meta["undeclared"] = sorted(read - set(env.keys()))
    meta["required_urls"] = re.findall(r'^\s*"(https://[^"]+)"\s*$', body, re.M)
    (tmp / "body.sh").write_text(body)
(tmp / "meta.json").write_text(json.dumps(meta))
PY

_meta="$TMP/meta.json"
_count="$(jq -r '.count' "$_meta")"

# C10 — exactly one step matches the name.
if [[ "$_count" == "1" ]]; then
  pass "C10: exactly one workflow step matches '${STEP_NAME}'"
else
  fail "C10: exactly one workflow step matches '${STEP_NAME}'" "n/a" "matched ${_count} steps"
  printf 'FAIL: cannot continue without exactly one step body\n'
  printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
  exit 1
fi

BODY="$TMP/body.sh"

# C11 — the `bash -e` premise, plus env-declaration completeness.
_has_shell="$(jq -r '.has_shell' "$_meta")"
_undeclared="$(jq -r '.undeclared | join(",")' "$_meta")"
if [[ "$_has_shell" == "false" && -z "$_undeclared" ]]; then
  pass "C11: the step declares no 'shell:' key (so 'bash -e' is faithful) and every \$VAR it reads is in env:"
else
  fail "C11: the step declares no 'shell:' key and every \$VAR it reads is in env:" "n/a" \
       "has_shell=${_has_shell} undeclared=[${_undeclared}] — if a shell: key was added, the faithful harness becomes 'bash --noprofile --norc -eo pipefail' and THIS SUITE'S HARNESS IS NOW STALE"
fi

# C12 — no `${{ }}`: an Actions expression is interpolated before bash ever sees it, so a body
# carrying one cannot be faithfully executed here at all.
if [[ "$(jq -r '.has_expr' "$_meta")" == "false" ]]; then
  pass "C12: the step body carries no \${{ }} expression, so executing it here is faithful"
else
  fail "C12: the step body carries no \${{ }} expression" "n/a" "the body interpolates an Actions expression"
fi

# FIXTURE URLs COME FROM THE WORKFLOW'S OWN required_urls ARRAY. Hard-coding them here would
# let a URL drift silently collapse the "URLs present" and "URLs missing" fixtures onto the
# same arm, so both printf branches would be driven by one of them and the other would never
# execute — which is the exact defect class this suite exists to close.
mapfile -t REQ_URLS < <(jq -r '.required_urls[]' "$_meta")
if [[ "${#REQ_URLS[@]}" -ne 3 ]]; then
  printf 'FAIL: expected 3 required_urls in the step body, found %s\n' "${#REQ_URLS[@]}"
  printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$((fails + 1))"
  exit 1
fi
ALL_URLS="$(printf '%s\n' "${REQ_URLS[@]}")"

# ── The gh stub ───────────────────────────────────────────────────────────────────
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Records argv, and answers `api` by running the body's OWN --jq expression through real jq
# against a fixture, emulating gh's pagination so --paginate/--slurp are observable.
set -uo pipefail
printf '%s\n' "$1 ${2:-}" >> "$GH_STUB_LOG"
case "${1:-}" in
  api)
    _expr=""; _paginate=0; _slurp=0
    for _a in "$@"; do
      case "$_a" in --paginate) _paginate=1 ;; --slurp) _slurp=1 ;; esac
    done
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--jq" ]] && { _expr="${2:-}"; break; }
      shift
    done
    [[ -n "$_expr" ]] || { echo "STUB: gh api without --jq" >&2; exit 99; }
    if [[ "$_paginate" -eq 1 && "$_slurp" -eq 1 ]]; then
      # gh --paginate --slurp yields ONE document: an array of per-page arrays.
      jq -c '[range(0; length; 30) as $i | .[$i:$i+30]]' "$GH_STUB_COMMENTS" | jq -r "$_expr"
    else
      # Unpaginated: a single page, capped at gh's 30-per-page default.
      jq -c '.[0:30]' "$GH_STUB_COMMENTS" | jq -r "$_expr"
    fi
    ;;
  issue)
    case "${2:-}" in
      view)   jq -r '.' "$GH_STUB_ISSUE_BODY" ;;
      reopen) # ONE LINE PER INVOCATION, so the count is never confused by the multi-line
              # --comment payload the body passes.
              printf 'reopen\n' >> "$GH_STUB_REOPEN_LOG"
              _n=$(wc -l < "$GH_STUB_REOPEN_LOG" | tr -d ' ')
              # The rendered --comment payload goes to its own file for content assertions.
              while [[ $# -gt 0 ]]; do
                [[ "$1" == "--comment" ]] && { printf '%s' "${2:-}" > "${GH_STUB_REOPEN_DIR}/${_n}.body"; break; }
                shift
              done ;;
      *) echo "STUB: unrecognised issue subcommand '${2:-}'" >&2; exit 99 ;;
    esac
    ;;
  run)
    [[ "${2:-}" == "view" ]] || { echo "STUB: unrecognised run subcommand" >&2; exit 99; }
    printf '%s\n' "$GH_STUB_RUN_CONCLUSION"
    ;;
  *) echo "STUB: unrecognised gh invocation '${1:-}'" >&2; exit 99 ;;
esac
STUB
chmod +x "$BIN/gh"

# ── The driver ────────────────────────────────────────────────────────────────────
#
# GH_REPO is an unroutable sentinel, ISSUE_NUM is 0, GH_TOKEN is empty and GH_CONFIG_DIR is a
# temp dir — so a real `gh` that somehow ran could not authenticate against anything, let
# alone mutate an issue.
GUARD_RC=0; GUARD_OUT=""; GUARD_REOPENS=0; GUARD_BODY=""
run_guard() {  # $1=comments-json-file $2=issue-body-json-file $3=run-conclusion
  local comments="$1" issuebody="$2" conclusion="$3"
  local rundir; rundir="$(mktemp -d "$TMP/run.XXXXXX")"
  : > "$rundir/gh.log"; : > "$rundir/reopen.log"; mkdir -p "$rundir/bodies"
  GUARD_OUT="$(
    PATH="$BIN:$PATH" \
    GH_STUB_LOG="$rundir/gh.log" \
    GH_STUB_REOPEN_LOG="$rundir/reopen.log" \
    GH_STUB_REOPEN_DIR="$rundir/bodies" \
    GH_STUB_COMMENTS="$comments" \
    GH_STUB_ISSUE_BODY="$issuebody" \
    GH_STUB_RUN_CONCLUSION="$conclusion" \
    GH_REPO="soleur-test/unroutable-sentinel" \
    ISSUE_NUM="0" \
    GH_TOKEN="" \
    GH_CONFIG_DIR="$rundir/ghcfg" \
    bash -e "$BODY" 2>&1
  )"; GUARD_RC=$?
  # Counted from a log with ONE LINE PER INVOCATION, never from the argv log: the body passes
  # a multi-line --comment, so a line-based count over argv would score one reopen as ~20.
  GUARD_REOPENS="$(wc -l < "$rundir/reopen.log" | tr -d ' ')"
  GUARD_BODY="$(cat "$rundir/bodies/1.body" 2>/dev/null || true)"
}

# THE STUB MUST BE WHAT `command -v gh` RESOLVES TO, asserted BEFORE any body runs. If the
# real gh shadowed it, every arm below would be measuring the wrong binary.
_resolved="$(PATH="$BIN:$PATH" command -v gh)"
if [[ "$_resolved" != "$BIN/gh" ]]; then
  printf 'FAIL: gh does not resolve to the stub (%s) — refusing to run against a real gh\n' "$_resolved"
  printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$((fails + 1))"
  exit 1
fi

# ── Fixture builders ──────────────────────────────────────────────────────────────
BOT='github-actions[bot]'
mk_comments() {  # $1=dest; remaining: login::body pairs, oldest first
  local dest="$1"; shift
  local first=1
  { printf '['
    for spec in "$@"; do
      [[ "$first" -eq 1 ]] || printf ','
      first=0
      jq -cn --arg l "${spec%%::*}" --arg b "${spec#*::}" '{user:{login:$l},body:$b}'
    done
    printf ']'
  } > "$dest"
}
ISSUE_PLAIN="$TMP/issue-plain.json"; printf '"an ordinary issue body"' > "$ISSUE_PLAIN"
ISSUE_SELF="$TMP/issue-self.json"
jq -n --arg b "$(printf '%s\nactions/runs/12345\nbytes: 4096\n' "$ALL_URLS")" '$b' > "$ISSUE_SELF"

COMPLETE_BODY="$(printf '%s\nhttps://github.com/o/r/actions/runs/12345\nbytes: 4096\n' "$ALL_URLS")"
INCOMPLETE_NO_URLS="closing this out, all done"
INCOMPLETE_NO_BYTES="$(printf '%s\nhttps://github.com/o/r/actions/runs/12345\n' "$ALL_URLS")"

# ── C1-C3: an incomplete closing comment reaches the reopen ───────────────────────
C_INC="$TMP/c-incomplete.json"; mk_comments "$C_INC" "someone::${INCOMPLETE_NO_URLS}"
run_guard "$C_INC" "$ISSUE_PLAIN" "failure"

if [[ "$GUARD_RC" -eq 0 ]]; then
  pass "C1: an incomplete closing comment under 'bash -e' exits 0 (the reopen is the signal)"
else
  fail "C1: an incomplete closing comment under 'bash -e' exits 0 (the reopen is the signal)" \
       "$GUARD_RC" "$GUARD_OUT"
fi

if [[ "$GUARD_REOPENS" -eq 1 ]]; then
  pass "C2: …and invokes 'gh issue reopen' exactly once"
else
  fail "C2: …and invokes 'gh issue reopen' exactly once" "$GUARD_RC" "reopens=${GUARD_REOPENS}"
fi

# C3 — BOTH printf arms of the missing-URLs conditional execute. One fixture exercises only
# one arm, so a `--` reverted on the other would go undetected; the second run below is what
# makes that impossible.
_c3a="$GUARD_BODY"
C_NOBYTES="$TMP/c-nobytes.json"; mk_comments "$C_NOBYTES" "someone::${INCOMPLETE_NO_BYTES}"
run_guard "$C_NOBYTES" "$ISSUE_PLAIN" "success"
_c3b="$GUARD_BODY"
if [[ "$_c3a" == *"**Verbatim callback URLs.**"* && "$_c3b" == *"[x] Verbatim callback URLs"* ]]; then
  pass "C3: both arms of the missing-URLs conditional render (the unchecked list AND the checked line)"
else
  fail "C3: both arms of the missing-URLs conditional render" "n/a" \
       "urls-missing-render=${_c3a:0:400} || urls-present-render=${_c3b:0:400}"
fi

# ── C4: a complete comment leaves the close standing ──────────────────────────────
C_OK="$TMP/c-complete.json"; mk_comments "$C_OK" "someone::${COMPLETE_BODY}"
run_guard "$C_OK" "$ISSUE_PLAIN" "success"
if [[ "$GUARD_RC" -eq 0 && "$GUARD_REOPENS" -eq 0 ]]; then
  pass "C4: a complete closing comment exits 0 with zero reopens"
else
  fail "C4: a complete closing comment exits 0 with zero reopens" "$GUARD_RC" "reopens=${GUARD_REOPENS} ${GUARD_OUT}"
fi

# ── C5: the guard must not read its own output ────────────────────────────────────
#
# THE DISCRIMINATING FIXTURE PUTS A COMPLETE HUMAN COMMENT BENEATH THE BOT COMMENT. The
# obvious fixture — bot comment newest, nothing else — does NOT discriminate: measured, the
# UNFIXED selector reopens once there too, because the bot's own reopen body satisfies field 1
# (it prints the missing URLs verbatim) but not fields 2 and 3 (it renders them as the literal
# templates `actions/runs/<id>` and `bytes: <N>`, with no digits). So "zero reopens" was never
# the pre-fix behaviour and that arm could not have reddened. Here the count genuinely moves
# 1 -> 0.
BOT_REOPEN_BODY="$(printf '## Closure gate: re-opening\n%s\n`https://github.com/o/r/actions/runs/<id>`\n`bytes: <N>`\n' "$ALL_URLS")"
C_BOT_OVER_OK="$TMP/c-bot-over-ok.json"
mk_comments "$C_BOT_OVER_OK" "someone::${COMPLETE_BODY}" "${BOT}::${BOT_REOPEN_BODY}"
run_guard "$C_BOT_OVER_OK" "$ISSUE_PLAIN" "success"
if [[ "$GUARD_RC" -eq 0 && "$GUARD_REOPENS" -eq 0 ]]; then
  pass "C5: a bot reopen body above a COMPLETE human comment yields zero reopens (no self-read)"
else
  fail "C5: a bot reopen body above a COMPLETE human comment yields zero reopens" \
       "$GUARD_RC" "reopens=${GUARD_REOPENS} ${GUARD_OUT}"
fi

# ── C6: …and the same shape over an INCOMPLETE human comment still reopens ────────
#
# Both the fixed and unfixed selectors reopen once here, so this arm discriminates on CONTENT:
# the rendered body must list the URLs actually missing from the HUMAN comment.
C_BOT_OVER_BAD="$TMP/c-bot-over-bad.json"
mk_comments "$C_BOT_OVER_BAD" "someone::${INCOMPLETE_NO_URLS}" "${BOT}::${BOT_REOPEN_BODY}"
run_guard "$C_BOT_OVER_BAD" "$ISSUE_PLAIN" "failure"
if [[ "$GUARD_REOPENS" -eq 1 && "$GUARD_BODY" == *"${REQ_URLS[0]}"* ]]; then
  pass "C6: a bot reopen body above an INCOMPLETE human comment reopens once, listing the missing URLs"
else
  fail "C6: a bot reopen body above an INCOMPLETE human comment reopens once, listing the missing URLs" \
       "$GUARD_RC" "reopens=${GUARD_REOPENS} body=${GUARD_BODY:0:400}"
fi

# ── C7: the filter is IDENTITY, not content ──────────────────────────────────────
#
# A body-content predicate ("skip comments containing '## Closure gate'") is a one-line bypass
# for anyone who can comment. A login is not: GitHub logins are alphanumeric-plus-hyphen, so
# `[bot]` cannot be spelled by a human account.
C_HUMAN_HEADING="$TMP/c-human-heading.json"
mk_comments "$C_HUMAN_HEADING" "someone::$(printf '## Closure gate: re-opening\n%s' "$INCOMPLETE_NO_URLS")"
run_guard "$C_HUMAN_HEADING" "$ISSUE_PLAIN" "failure"
if [[ "$GUARD_REOPENS" -eq 1 ]]; then
  pass "C7: a HUMAN comment carrying the guard's own heading is NOT excluded (identity filter)"
else
  fail "C7: a HUMAN comment carrying the guard's own heading is NOT excluded (identity filter)" \
       "$GUARD_RC" "reopens=${GUARD_REOPENS}"
fi

# ── C8: pagination ────────────────────────────────────────────────────────────────
#
# gh api is unpaginated by default at 30 per page, so on a long thread `.[-1]` selects comment
# #30 — an unrelated historical comment — and the guard validates the wrong thing entirely.
C_31="$TMP/c-31.json"
_specs=(); for _i in $(seq 1 30); do _specs+=("someone::filler comment ${_i}"); done
_specs+=("someone::${COMPLETE_BODY}")
mk_comments "$C_31" "${_specs[@]}"
run_guard "$C_31" "$ISSUE_PLAIN" "success"
if [[ "$GUARD_RC" -eq 0 && "$GUARD_REOPENS" -eq 0 ]]; then
  pass "C8: on a 31-comment thread the NEWEST comment is selected, not comment #30"
else
  fail "C8: on a 31-comment thread the NEWEST comment is selected, not comment #30" \
       "$GUARD_RC" "reopens=${GUARD_REOPENS} — comment #30 is filler, so a reopen here means the selector read the wrong comment"
fi

# ── C9: no qualifying comment must REOPEN, not satisfy itself from the issue body ─
#
# The issue body is authored by whoever opened the issue, and a callback-URL follow-through
# body legitimately contains all three URLs (verified on #1784) — so a body fallback lets an
# issue satisfy its own gate, and excluding bot comments makes that path MORE reachable.
C_BOT_ONLY="$TMP/c-bot-only.json"; mk_comments "$C_BOT_ONLY" "${BOT}::${BOT_REOPEN_BODY}"
run_guard "$C_BOT_ONLY" "$ISSUE_SELF" "success"
if [[ "$GUARD_REOPENS" -eq 1 ]]; then
  pass "C9: with no qualifying comment and a self-satisfying issue body, the guard REOPENS"
else
  fail "C9: with no qualifying comment and a self-satisfying issue body, the guard REOPENS" \
       "$GUARD_RC" "reopens=${GUARD_REOPENS} — the issue body must not satisfy its own gate"
fi

# ── C13: the standing repo-wide sweep ─────────────────────────────────────────────
#
# THREE BOUNDS, STATED RATHER THAN LEFT FOR A READER TO INFER — this is a floor on the class,
# not a proof of absence:
#   (1) single-quoted formats only. Double-quoted `printf "-…"` is not matched. This
#       deliberately excludes awk program text, where `printf "- …"` parses no options at all.
#   (2) start-of-line call sites only. A mid-line `… && printf '-…'` is not matched.
#   (3) POSIX classes, never `\s` — `\s` is a GNU ERE extension and silently matches a literal
#       `s` on other greps, which would make this sweep quietly stop finding anything.
#
# The repo's bar for minting a `scripts/lint-*` gate was six occurrences across six files;
# this class has two in one file, so it stays an assertion here rather than a lint.
SWEEP_RE='^[[:space:]]*printf[[:space:]]+.-'
sweep() {  # $1 = root to scan; prints matching "file:line" records
  grep -rnE --binary-files=without-match --exclude-dir=archive \
    "$SWEEP_RE" "$1" 2>/dev/null | grep -E "printf[[:space:]]+'-" || true
}
_scanned=0
for _d in .github scripts plugins tests apps; do
  [[ -d "$ROOT/$_d" ]] || continue
  _scanned=$((_scanned + $(find "$ROOT/$_d" -type f 2>/dev/null | wc -l)))
done
_real_hits="$(for _d in .github scripts plugins tests apps; do
    [[ -d "$ROOT/$_d" ]] && sweep "$ROOT/$_d"
  done | wc -l | tr -d ' ')"

# Fireability: a planted violation must be found, and one planted in an EXCLUDED path must not.
PLANT="$TMP/plant"; mkdir -p "$PLANT/archive"
printf "printf '\\055 x\\\\n'\n" | sed 's/\\055/-/' > "$PLANT/violation.sh"
printf "printf '\\055 x\\\\n'\n" | sed 's/\\055/-/' > "$PLANT/archive/violation.sh"
printf "# prose: never write printf '\\055 …' without the guard\n" | sed 's/\\055/-/' > "$PLANT/prose.sh"
_plant_hits="$(sweep "$PLANT" | wc -l | tr -d ' ')"
_plant_files="$(sweep "$PLANT" | cut -d: -f1 | sort -u | xargs -r -n1 basename | paste -sd, -)"

if [[ "$_real_hits" -eq 0 && "$_scanned" -gt 0 && "$_plant_hits" -eq 1 && "$_plant_files" == "violation.sh" ]]; then
  pass "C13: the repo-wide printf '- sweep returns zero over ${_scanned} scanned files, fires on a planted violation, and ignores excluded paths and prose"
else
  fail "C13: the repo-wide printf '- sweep is clean, fireable, and correctly bounded" "n/a" \
       "real_hits=${_real_hits} scanned=${_scanned} plant_hits=${_plant_hits} plant_files=[${_plant_files}] (want real=0 scanned>0 plant=1 files=violation.sh)"
fi

# ── Anti-vacuity floor ────────────────────────────────────────────────────────────
#
# EXACT, not a floor, and deliberately unlike its sibling suites. Those are broad and
# developer-incremented, where an equality would redden on every legitimate addition. This
# suite is a closed set of 13 named arms C1-C13 enumerated in the plan's Guard 3 matrix, so
# the count is a specification rather than a running total: an arm that stops running is the
# failure mode, and delete-one-add-one is exactly what a floor cannot see.
_ran=$((passes + fails))
if [[ "$_ran" -ne 13 ]]; then
  fails=$((fails + 1))
  printf 'FAIL: ANTI-VACUITY: %s assertions ran, expected exactly 13 (C1-C13). An arm was deleted, skipped, added without updating this count, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity: exactly %s assertions ran (C1-C13)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
