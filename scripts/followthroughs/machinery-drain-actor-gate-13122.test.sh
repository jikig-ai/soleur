#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/machinery-drain-actor-gate-13122.sh.
# Values are synthesized (cq-test-fixtures-synthesized-only): all run/job ids and dates are made up.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/machinery-drain-actor-gate-13122.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

pass "instrument self-test (pass path)"
fail "instrument self-test (fail path, EXPECTED and discounted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'harness: instrument self-test did not move both counters (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0
echo "--- instrument verified; counters reset ---"

[[ -f "$PROBE" ]] || abort "the probe is missing at $PROBE"
command -v jq >/dev/null || abort "jq is required"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *) printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

ROOT="$(mktemp -d "${TMPDIR:-/var/tmp}/mdag-13122.XXXXXXXX")" || abort "mktemp -d failed"
assert_fixture_dir "$ROOT"
[[ -d "$ROOT" && ! -L "$ROOT" ]] || abort "scratch root is not a plain directory: $ROOT"
readonly ROOT
trap 'rm -rf -- "$ROOT"' EXIT
STUBDIR="$ROOT/bin"
FX="$ROOT/fx"
OUT="$ROOT/out.txt"
ERR="$ROOT/err.txt"
mkdir -p "$STUBDIR" "$FX" "$ROOT/home"

cat > "$STUBDIR/gh" <<'STUB'
#!/usr/bin/env bash
FX="${FX:?}"
printf '%s\n' "$*" >> "$FX/calls.log"
unexpected() { printf '%s\n' "$*" >> "$FX/unexpected"; echo "stub gh: unexpected request: $*" >&2; exit 64; }
if [[ -f "$FX/gh_fail" ]]; then echo 'stub gh: injected failure' >&2; exit 1; fi
[[ "${1:-}" == api ]] || unexpected "$@"
endpoint="${2:-}"
if [[ "$endpoint" == --allow-escape-sequences ]]; then endpoint="${3:-}"; fi
case "$endpoint" in
  'repos/jikig-ai/soleur/actions/workflows/scheduled-machinery-drain.yml/runs?actor=soleur-ai%5Bbot%5D&status=completed&event=workflow_dispatch&created=%3E%3D2026-11-28T12%3A57%3A15Z&per_page=100')
    cat "$FX/runs.json" ;;
  repos/jikig-ai/soleur/actions/runs/*/jobs?per_page=100)
    id="$endpoint"
    id="${id#repos/jikig-ai/soleur/actions/runs/}"
    id="${id%%/jobs?per_page=100}"
    [[ -f "$FX/jobs_$id.json" ]] && cat "$FX/jobs_$id.json" || unexpected "$@" ;;
  repos/jikig-ai/soleur/actions/jobs/*/steps/*/logs)
    rest="${endpoint#repos/jikig-ai/soleur/actions/jobs/}"
    job="${rest%%/steps/*}"
    step="${rest##*/steps/}"
    step="${step%%/logs}"
    [[ -f "$FX/log_${job}_${step}.txt" ]] && cat "$FX/log_${job}_${step}.txt" || unexpected "$@" ;;
  repos/jikig-ai/soleur/issues/9508/comments?since=*\&per_page=100)
    cat "$FX/comments.json" ;;
  *) unexpected "$@" ;;
esac
STUB
chmod +x "$STUBDIR/gh"

TS='2026-11-30T09:04:29.4658081Z'
write_logs() {
  local drain_mode="$1" closed="$2" crlf="${3:-}"
  {
    printf '%s ##[group]Run anthropics/claude-code-action@v1.0.263\n' "$TS"
    case "$drain_mode" in
      refusal)
        printf '%s ##[error]Action failed with error: Workflow initiated by non-human actor: soleur-ai (type: Bot). Add bot to allowed_bots list or use '\''*'\'' to allow all bots.\n' "$TS" ;;
      echo-only)
        printf '%s \033[36;1mecho "Workflow initiated by non-human actor: soleur-ai (type: Bot)"\033[0m\n' "$TS" ;;
      generic)
        printf '%s ##[error]Process completed with exit code 1.\n' "$TS" ;;
      substantive)
        printf '%s ##[error]drain query failed: permission denied for relation machinery_candidates\n' "$TS"
        printf '%s ##[error]Process completed with exit code 1.\n' "$TS" ;;
    esac
    printf '%s drain complete: closed=%s\n' "$TS" "$closed"
  } > "$FX/log_777_5.txt"
  if [[ -n "$crlf" ]]; then sed -i 's/$/\r/' "$FX/log_777_5.txt"; fi
  {
    printf '%s \033[36;1mecho "updated standing issue #$existing"\033[0m\n' '2026-11-30T09:04:32.1000000Z'
    printf '%s updated standing issue #9508\n' '2026-11-30T09:04:32.5899400Z'
  } > "$FX/log_777_7.txt"
}

write_world() {
  local mode="$1"
  rm -f "$FX"/runs.json "$FX"/jobs_*.json "$FX"/log_*.txt "$FX"/comments.json "$FX"/calls.log "$FX"/unexpected "$FX"/gh_fail
  write_logs clean 3
  case "$mode" in
    empty)
      printf '{"total_count":0,"workflow_runs":[]}\n' > "$FX/runs.json" ;;
    overflow)
      printf '{"total_count":101,"workflow_runs":[]}\n' > "$FX/runs.json" ;;
    wrong-actor)
      printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":111,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"renovate[bot]"}}]}' > "$FX/runs.json" ;;
    cancelled-first)
      printf '%s\n' '{"total_count":2,"workflow_runs":[{"id":112,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"cancelled","triggering_actor":{"login":"soleur-ai[bot]"}},{"id":111,"created_at":"2026-11-30T09:04:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}}]}' > "$FX/runs.json"
      printf '%s\n' '{"jobs":[{"id":777,"name":"measure-and-drain","steps":[{"name":"Drain the machinery ledger","number":5,"conclusion":"success"},{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_111.json"
      printf '%s\n' '[{"created_at":"2026-11-30T09:05:32Z","user":{"login":"github-actions[bot]"},"body":"Machinery drain outcome:\n\n~~~\nbefore=363 after=360 closed=3 floor=20\n~~~"}]' > "$FX/comments.json" ;;
    malformed-runs)
      printf 'not json\n' > "$FX/runs.json" ;;
    stale-comment)
      printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":111,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}}]}' > "$FX/runs.json"
      printf '%s\n' '{"jobs":[{"id":777,"name":"measure-and-drain","steps":[{"name":"Drain the machinery ledger","number":5,"conclusion":"success"},{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_111.json"
      printf '%s\n' '[{"created_at":"2026-11-23T09:04:32Z","user":{"login":"github-actions[bot]"},"body":"Machinery drain outcome:\n\n~~~\nbefore=363 after=360 closed=3 floor=20\n~~~"}]' > "$FX/comments.json" ;;
    decoy-comment)
      printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":111,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}}]}' > "$FX/runs.json"
      printf '%s\n' '{"jobs":[{"id":777,"name":"measure-and-drain","steps":[{"name":"Drain the machinery ledger","number":5,"conclusion":"success"},{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_111.json"
      printf '%s\n' '[{"created_at":"2026-11-30T09:04:32Z","user":{"login":"github-actions[bot]"},"body":"Machinery drain outcome:\n\nincidental prose closed=99 but no measurement line"}]' > "$FX/comments.json" ;;
    *)
      printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":111,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}}]}' > "$FX/runs.json"
      printf '%s\n' '{"jobs":[{"id":777,"name":"measure-and-drain","steps":[{"name":"Drain the machinery ledger","number":5,"conclusion":"success"},{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_111.json"
      printf '%s\n' '[{"created_at":"2026-11-30T09:04:32Z","user":{"login":"github-actions[bot]"},"body":"Machinery drain outcome:\n\n~~~\nbefore=363 after=360 closed=3 floor=20\n~~~"}]' > "$FX/comments.json" ;;
  esac
}

run_probe() {
  : > "$OUT"; : > "$ERR"
  PATH="$STUBDIR:/usr/bin:/bin" HOME="$ROOT/home" FX="$FX" GH_TOKEN=synthetic bash "$PROBE" >"$OUT" 2>"$ERR"
  echo $?
}

expect() {
  local name="$1" want_rc="$2" got_rc="$3"
  if [[ "$got_rc" -eq "$want_rc" && ! -s "$FX/unexpected" ]]; then
    pass "$name"
  else
    fail "$name (wanted rc=$want_rc got rc=$got_rc unexpected=$(cat "$FX/unexpected" 2>/dev/null || true); stdout=$(tail -2 "$OUT"); stderr=$(tail -2 "$ERR"))"
  fi
}

# The probe does not exist yet at RED time; every behavioral row must fail then.
unset GH_TOKEN
PATH="$STUBDIR:/usr/bin:/bin" HOME="$ROOT/home" FX="$FX" bash "$PROBE" >"$OUT" 2>"$ERR"
[[ $? -eq 3 ]] && pass 'missing GH_TOKEN -> 3' || fail 'missing GH_TOKEN -> 3'

write_world empty; expect 'no qualifying completed measurement -> 2' 2 "$(run_probe)"

write_world pass; expect 'clean post-cutoff measurement with closed=3 -> 0' 0 "$(run_probe)"

write_world pass; write_logs refusal 0; expect 'emitted actor refusal -> 1' 1 "$(run_probe)"

write_world pass; write_logs echo-only 3; expect 'colourised echoed source actor text is not a refusal' 0 "$(run_probe)"

write_world pass; write_logs clean 0; sed -i 's/before=363 after=360 closed=3 floor=20/before=363 after=363 closed=0 floor=20 WAIVED-POOL-EMPTY/' "$FX/comments.json"; expect 'explicit WAIVED closed=0 -> 0' 0 "$(run_probe)"

write_world pass; write_logs substantive 0; sed -i 's/before=363 after=360 closed=3 floor=20/before=363 after=363 closed=0 floor=20/' "$FX/comments.json"; expect 'substantive non-actor error diagnoses closed=0 -> 0' 0 "$(run_probe)"

write_world pass; write_logs generic 0; sed -i 's/before=363 after=360 closed=3 floor=20/before=363 after=363 closed=0 floor=20/' "$FX/comments.json"; expect 'unexplained closed=0 with generic process error -> 3' 3 "$(run_probe)"

write_world stale-comment; expect 'stale standing-issue comment is not evidence -> 3' 3 "$(run_probe)"
write_world decoy-comment; expect 'decoy closed token outside outcome block is not evidence -> 3' 3 "$(run_probe)"
write_world overflow; expect 'incomplete newest page -> 3' 3 "$(run_probe)"
write_world wrong-actor; expect 'non-soleur actor row is not a measurement -> 2' 2 "$(run_probe)"
write_world cancelled-first; expect 'cancelled rows skip to first non-cancelled measurement' 0 "$(run_probe)"
write_world malformed-runs; expect 'malformed runs response -> 3' 3 "$(run_probe)"

write_world pass; touch "$FX/gh_fail"; expect 'gh failure -> 3' 3 "$(run_probe)"

write_world pass; write_logs clean 3 crlf; expect 'CRLF step logs -> 0' 0 "$(run_probe)"

PATH="$STUBDIR:/usr/bin:/bin" HOME="$ROOT/home" FX="$FX" GH_TOKEN=synthetic bash -x "$PROBE" >"$OUT" 2>"$ERR"
[[ $? -eq 78 ]] && pass 'xtrace with GH_TOKEN -> 78' || fail 'xtrace with GH_TOKEN -> 78'

# Mutation rows: a mutant is "detected" when it changes the correct verdict for its fixture.
make_mutant() {
  local mode="$1" dest="$2"
  python3 - "$PROBE" "$dest" "$mode" <<'PYM'
import sys
src, dest, mode = sys.argv[1:4]
text = open(src).read()
if mode == 'bare-refusal':
    lines = ['REFUSAL_RE="Workflow initiated by non-human actor"' if line.startswith('REFUSAL_RE=') else line for line in text.splitlines()]
    text = '\n'.join(lines) + '\n'
elif mode == 'skip-drain-scan':
    needle = 'if grep -aEq "$REFUSAL_RE" "$DRAIN_LOG.clean"; then'
    assert needle in text
    text = text.replace(needle, 'if false; then', 1)
elif mode == 'newest-first':
    needle = '| sort_by(.created_at)'
    assert needle in text
    text = text.replace(needle, '| sort_by(.created_at) | reverse', 1)
else:
    raise SystemExit('unknown mutant mode')
open(dest, 'w').write(text)
PYM
  chmod +x "$dest"
}

run_file() {
  local file="$1"
  : > "$OUT"; : > "$ERR"
  PATH="$STUBDIR:/usr/bin:/bin" HOME="$ROOT/home" FX="$FX" GH_TOKEN=synthetic bash "$file" >"$OUT" 2>"$ERR"
  echo $?
}

expect_mutant_detected() {
  local name="$1" correct_rc="$2" mutant_rc="$3"
  if [[ "$mutant_rc" != "$correct_rc" ]]; then pass "$name"; else fail "$name (mutant preserved correct rc=$correct_rc)"; fi
}

write_world pass; write_logs echo-only 3
make_mutant bare-refusal "$ROOT/mutant-bare.sh"
expect_mutant_detected 'mutation M1 bare refusal sentence is caught by echoed-source fixture' 0 "$(run_file "$ROOT/mutant-bare.sh")"

write_world pass; write_logs refusal 0
make_mutant skip-drain-scan "$ROOT/mutant-skip.sh"
expect_mutant_detected 'mutation M2 skipping the Drain step-log scan is caught by refusal fixture' 1 "$(run_file "$ROOT/mutant-skip.sh")"

write_world pass
printf '%s
' '{"total_count":2,"workflow_runs":[{"id":111,"created_at":"2026-11-30T09:03:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}},{"id":112,"created_at":"2026-11-30T09:05:54Z","event":"workflow_dispatch","head_branch":"main","conclusion":"failure","triggering_actor":{"login":"soleur-ai[bot]"}}]}' > "$FX/runs.json"
printf '%s
' '{"jobs":[{"id":888,"name":"measure-and-drain","steps":[{"name":"Drain the machinery ledger","number":5,"conclusion":"success"},{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_112.json"
cp "$FX/log_777_7.txt" "$FX/log_888_7.txt"
write_logs refusal 0; mv "$FX/log_777_5.txt" "$FX/log_888_5.txt"; write_logs clean 3
printf '%s
' '[{"created_at":"2026-11-30T09:04:32Z","user":{"login":"github-actions[bot]"},"body":"Machinery drain outcome:

~~~
before=363 after=360 closed=3 floor=20
~~~"}]' > "$FX/comments.json"
make_mutant newest-first "$ROOT/mutant-newest.sh"
expect_mutant_detected 'mutation M3 newest-first selection is caught when verdicts differ' 0 "$(run_file "$ROOT/mutant-newest.sh")"

write_world pass
printf '%s
' '[{"created_at":"2026-11-30T09:04:32Z","user":{"login":"soleur-ai[bot]"},"body":"Machinery drain outcome:

~~~
before=363 after=360 closed=3 floor=20
~~~"}]' > "$FX/comments.json"
expect 'wrong-author outcome comment is not evidence -> 3' 3 "$(run_probe)"

write_world pass
printf '%s
' '{"jobs":[{"id":777,"name":"measure-and-drain","steps":[{"name":"Update the standing measurement issue","number":7,"conclusion":"success"}]}]}' > "$FX/jobs_111.json"
expect 'missing exact Drain step evidence -> 3' 3 "$(run_probe)"

PATH="$STUBDIR:/usr/bin:/bin" FX="$FX" gh api deliberately-unexpected >"$OUT" 2>"$ERR"
[[ $? -eq 64 && -s "$FX/unexpected" ]] && pass 'strict gh stub exits 64 on an unexpected request shape' || fail 'strict gh stub exits 64 on an unexpected request shape'
: > "$FX/unexpected"

echo "passes=$passes fails=$fails"
[[ "$fails" -eq 0 && "$passes" -gt 0 ]]
