#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard — the ci.yml classify steps (`e2e`, `shard-totality-mutations`) DECIDE correctly when EXECUTED (#9729).
#
# PROPERTY. The run: block of each `Classify … applicability` step, extracted from ci.yml and executed under the
# shell Actions uses (`bash --noprofile --norc -eo pipefail`) against a real git fixture, (1) emits `applicable=false`
# for a markdown-only pull request whose base ref carries the classifier, (2) emits `applicable=true` for a code
# diff, and (3) when the diff cannot be resolved (no `origin/<base>` ref, i.e. a shallow clone) falls back to
# `applicable=true` AND names the measured cause in its warning instead of discarding git's stderr.
#
# WHY EXECUTED. A text pin certified `fetch-depth: ... && 0 || 1` for weeks while the expression evaluated to 1 and
# every pull request fell back; the wiring anchors in ci-e2e-skip-anchors.test.sh and ci-shard-totality-skip.test.sh
# pin spelling, this suite pins behaviour.
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0
# One owning root for every fixture, removed on ANY exit path (a die between allocation and the per-case rm would
# otherwise leak the fixture repository).
WORK_ROOT="$(mktemp -d "${TMPDIR:-/var/tmp}/ci-classify-exec.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK_ROOT"' EXIT
pass() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)" >/dev/null
fail "instrument self-test (expected, subtracted)" >/dev/null
if [ "$PASS" -ne $((_p0 + 1)) ] || [ "$FAIL" -ne $((_f0 + 1)) ]; then
  printf 'FATAL: pass()/fail() did not each move their counter\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# Extract the run: block of a named step inside a named job. One PyYAML program, not a regex over text.
extract_step() { # <job> <step-name-prefix> <out-file>
  python3 - "$CI_YML" "$1" "$2" "$3" <<'PY'
import sys, yaml
path, job, prefix, out = sys.argv[1:5]
doc = yaml.safe_load(open(path))
for step in doc["jobs"][job]["steps"]:
    if str(step.get("name", "")).startswith(prefix):
        open(out, "w").write(step["run"])
        sys.exit(0)
sys.stderr.write("step not found: %s / %s\n" % (job, prefix))
sys.exit(3)
PY
}

# run_case <job> <step-prefix> <classifier-relpath> <mode> <expect-verdict> [warn-needle]
#   mode = md      : markdown-only PR diff, base ref carries the classifier
#          code    : app-code PR diff, base ref carries the classifier
#          shallow : no origin/<base> ref at all (the depth-1 clone shape)
run_case() {
  local job="$1" prefix="$2" classifier="$3" mode="$4" expect="$5" needle="${6-}"
  local root work out step_file rc got warn
  assert_fixture_dir "$WORK_ROOT"
  root="$WORK_ROOT/$job-$mode"
  mkdir -p "$root" || { fail "mkdir failed ($job/$mode)"; return; }
  assert_fixture_dir "$root"
  work="$root/work"
  out="$root/github_output"
  step_file="$root/step.sh"
  mkdir -p "$work" "$root/tmp"
  extract_step "$job" "$prefix" "$step_file" || { fail "extract step ($job/$mode)"; rm -rf "$root"; return; }

  local g=(env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
           -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_CEILING_DIRECTORIES
           GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
           GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git -C "$work")
  "${g[@]}" init -q -b main
  mkdir -p "$work/scripts" "$work/knowledge-base"
  cp "$REPO_ROOT/$classifier" "$work/$classifier"
  printf 'x\n' > "$work/knowledge-base/a.md"
  "${g[@]}" add -A
  "${g[@]}" commit -q -m base
  if [ "$mode" != "shallow" ]; then
    "${g[@]}" update-ref refs/remotes/origin/main HEAD
  fi
  "${g[@]}" checkout -q -b pr
  if [ "$mode" = "code" ]; then
    mkdir -p "$work/apps"
    printf 'y\n' > "$work/apps/x.ts"
  else
    printf 'z\n' > "$work/knowledge-base/a.md"
  fi
  "${g[@]}" add -A
  "${g[@]}" commit -q -m change

  : > "$out"
  warn="$root/stdout"
  # The cwd is the fixture repo; the step reads scripts/<classifier> from it on the fallback path. HOME and
  # the global config are pinned so the host's gitconfig cannot change the verdict.
  (
    cd "$work" || exit 97
    env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE \
      HOME="$root" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      EVENT_NAME=pull_request GITHUB_BASE_REF=main RUNNER_TEMP="$root/tmp" GITHUB_OUTPUT="$out" \
      bash --noprofile --norc -eo pipefail "$step_file"
  ) > "$warn" 2>&1
  rc=$?
  got="$(sed -n 's/^applicable=//p' "$out" | tail -1)"
  if [ "$rc" -eq 0 ] && [ "$got" = "$expect" ]; then
    pass "$job/$mode: applicable=$expect"
  else
    fail "$job/$mode: want applicable=$expect got='${got}' rc=$rc ($(tr '\n' ' ' < "$warn" | cut -c1-200))"
  fi
  if [ -n "$needle" ]; then
    if grep -qF -e "$needle" "$warn"; then
      pass "$job/$mode: warning names the measured cause ($needle)"
    else
      fail "$job/$mode: warning lacks '$needle' ($(tr '\n' ' ' < "$warn" | cut -c1-200))"
    fi
  fi
  rm -rf "$root"
}

for spec in \
  "e2e|Classify e2e applicability|scripts/ci-e2e-classify.sh" \
  "shard-totality-mutations|Classify shard-totality applicability|scripts/ci-shard-totality-classify.sh"; do
  job="${spec%%|*}"; rest="${spec#*|}"; prefix="${rest%%|*}"; classifier="${rest#*|}"
  echo "── $job"
  run_case "$job" "$prefix" "$classifier" md      false
  run_case "$job" "$prefix" "$classifier" code    true
  run_case "$job" "$prefix" "$classifier" shallow true "base_ref_resolves=no"
done

total=$((PASS + FAIL))
if [ "$total" -lt 8 ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, want >=8\n' "$total" >&2
  exit 1
fi
echo
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
