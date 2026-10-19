#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard — the ci.yml classify steps (`e2e`, `shard-totality-mutations`) DECIDE correctly when EXECUTED (#9729).
#
# PROPERTY. The run: block of each `Classify … applicability` step, extracted from ci.yml and executed under the
# shell Actions uses (`bash --noprofile --norc -eo pipefail`) against a real git fixture, (1) emits `applicable=false`
# for a markdown-only pull request whose base ref carries the classifier, (2) emits `applicable=true` for a code
# diff, (2b) emits `applicable=true` when the markdown is not an ordinary file (an added symlinked `.md`, an added
# exec-bit `.md`, an exec-bit flip on a tracked `.md`: #10416, the modes come from REAL `git diff --raw` output), and
# (2c) emits `applicable=true` when the BASE ref still carries the pre-change (name-status) classifier and so cannot
# read the new raw feed (the self-judging transition of the PR that introduced the feed), and (3) when the diff cannot be resolved (no `origin/<base>` ref, i.e. a shallow clone) falls back to
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
WORK_ROOT="$(mktemp -d "${TMPDIR:-/var/tmp}/ci-classify-exec.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK_ROOT"
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

# FROZEN copy of the PRE-change (#10416) classifier parse: the first whitespace token of a row is the status. It is the
# base-ref copy the `transition` mode plants, so the test never depends on what origin/main holds today. Fed the new raw rows
# its status token is `:100644`, which is neither M nor A, so it fails closed. `arm` is the one allowlist arm that differs.
frozen_classifier() { # <job: e2e|shard>
  local arm='knowledge-base/*) ;;'
  [ "$1" = shard ] && arm='knowledge-base/*.md) ;;'
  cat <<EOF
#!/usr/bin/env bash
set -uo pipefail
emit() { printf '%s\n' "\$1"; exit 0; }
event="\${1:-}"
case "\$event" in
  --enum-failed) emit true ;;
  pull_request) ;;
  *) emit true ;;
esac
saw_any=0
while IFS= read -r line || [ -n "\$line" ]; do
  [ -z "\$line" ] && continue
  saw_any=1
  if [[ "\$line" == *[[:space:]]* ]]; then
    status="\${line%%[[:space:]]*}"
    rest="\${line#"\$status"}"
    path="\${rest#"\${rest%%[![:space:]]*}"}"
  else
    status="M"
    path="\$line"
  fi
  case "\$status" in
    M|A) ;;
    *) emit true ;;
  esac
  case "\$path" in
    $arm
    *.md)
      case "\$path" in */*) emit true ;; esac ;;
    *) emit true ;;
  esac
done
[ "\$saw_any" -eq 1 ] || emit true
emit false
EOF
}

# run_case <job> <step-prefix> <classifier-relpath> <mode> <expect-verdict> [warn-needle...]
#   mode = md      : markdown-only PR diff, base ref carries the classifier
#          code    : app-code PR diff, base ref carries the classifier
#          shallow : no origin/<base> ref at all (the depth-1 clone shape)
#          weak    : code diff, and the CHECKED-OUT classifier is replaced by one that always says false (uncommitted, so it is
#                    not in the diff): the step must judge by the BASE ref's copy, so the verdict stays true
#          mixed   : a markdown row sorted BEFORE a code row in one diff: every row must be read, not only the first
#          symlink : an ADDED symlinked `.md` (git mode 120000) under knowledge-base/: not markdown, so the job runs
#          execbit : an ADDED executable `.md` (git mode 100755)
#          modeflip: an exec-bit flip (100644 -> 100755) on a tracked root README.md
#          typechg : a tracked root README.md replaced by a symlink (git T row, 100644 -> 120000)
#          delete  : a tracked root README.md deleted (git D row)
#          transition: a markdown-only diff, but the BASE ref carries the FROZEN pre-change classifier, which cannot read raw rows
#          big     : a code row first, then ~1500 markdown rows (> 64 KB listing): the early-exit classifier must not
#                    SIGPIPE the producer and red the step
run_case() {
  local job="$1" prefix="$2" classifier="$3" mode="$4" expect="$5"; shift 5
  local root work out step_file rc got warn
  assert_fixture_dir "$WORK_ROOT"
  root="$WORK_ROOT/$job-$mode"
  mkdir -p "$root" || { fail "mkdir failed ($job/$mode)"; return; }
  assert_fixture_dir "$root"
  work="$root/work"
  assert_fixture_dir "$work"
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
  if [ "$mode" = "transition" ]; then
    case "$job" in shard-totality-mutations) frozen_classifier shard ;; *) frozen_classifier e2e ;; esac > "$work/$classifier"
  else
    cp "$REPO_ROOT/$classifier" "$work/$classifier"
  fi
  printf 'x\n' > "$work/knowledge-base/a.md"
  printf 'readme\n' > "$work/README.md"
  "${g[@]}" add -A
  "${g[@]}" commit -q -m base
  if [ "$mode" != "shallow" ]; then
    "${g[@]}" update-ref refs/remotes/origin/main HEAD
  fi
  "${g[@]}" checkout -q -b pr
  case "$mode" in
    code|weak)
      mkdir -p "$work/apps"
      printf 'y\n' > "$work/apps/x.ts" ;;
    mixed)
      mkdir -p "$work/zz"
      printf 'z\n' > "$work/knowledge-base/a.md"
      printf 'y\n' > "$work/zz/x.ts" ;;
    symlink)
      ln -s ../README.md "$work/knowledge-base/link.md" ;;
    execbit)
      printf 'z\n' > "$work/knowledge-base/exec.md" ;;
    modeflip)
      : ;;
    typechg)
      rm -f "$work/README.md"
      ln -s knowledge-base/a.md "$work/README.md" ;;
    delete)
      rm -f "$work/README.md" ;;
    big)
      mkdir -p "$work/aa" "$work/knowledge-base/big"
      printf 'y\n' > "$work/aa/x.ts"
      local i=0
      while [ "$i" -lt 1500 ]; do
        printf 'z\n' > "$work/knowledge-base/big/a-rather-long-markdown-file-name-to-fill-the-pipe-buffer-$i.md"
        i=$((i + 1))
      done ;;
    *)
      printf 'z\n' > "$work/knowledge-base/a.md" ;;
  esac
  "${g[@]}" add -A
  case "$mode" in
    execbit)  "${g[@]}" update-index --chmod=+x knowledge-base/exec.md ;;
    modeflip) "${g[@]}" update-index --chmod=+x README.md ;;
  esac
  "${g[@]}" commit -q -m change
  if [ "$mode" = "weak" ]; then
    printf '#!/usr/bin/env bash\nprintf "false\\n"\n' > "$work/$classifier"
  fi

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
  # A true verdict must come from the classifier refusing the rows, not from the enum-failed fallback (a broken diff feed also
  # prints true): the fallback's warning must be absent for every mode that reaches the classifier with a real diff.
  case "$mode" in
    symlink|execbit|modeflip|typechg|delete|transition)
      if grep -qF 'fell back to enum-failed' "$warn"; then
        fail "$job/$mode: true came from the enum-failed fallback, not the classifier ($(tr '\n' ' ' < "$warn" | cut -c1-200))"
      else
        pass "$job/$mode: verdict came from the classifier, not the enum-failed fallback"
      fi ;;
  esac
  local needle
  for needle in "$@"; do
    if grep -qF -e "$needle" "$warn"; then
      pass "$job/$mode: warning names the measured cause ($needle)"
    else
      fail "$job/$mode: warning lacks '$needle' ($(tr '\n' ' ' < "$warn" | cut -c1-200))"
    fi
  done
  rm -rf "$root"
}

# Control on the transition instrument: the frozen pre-change classifier must say false on a legacy name-status markdown row,
# otherwise a heredoc that always fails closed would keep the `transition` case green for the wrong reason.
for _arm in e2e shard; do
  _fz="$WORK_ROOT/frozen-$_arm.sh"
  frozen_classifier "$_arm" > "$_fz"
  _fv="$(printf 'M\tknowledge-base/a.md\n' | bash "$_fz" pull_request 2>&1)"
  if [ "$_fv" = false ]; then pass "frozen $_arm classifier reads a name-status markdown row as false (control)"
  else fail "frozen $_arm classifier control: want false got '$_fv'"; fi
done

for spec in \
  "e2e|Classify e2e applicability|scripts/ci-e2e-classify.sh" \
  "shard-totality-mutations|Classify shard-totality applicability|scripts/ci-shard-totality-classify.sh"; do
  job="${spec%%|*}"; rest="${spec#*|}"; prefix="${rest%%|*}"; classifier="${rest#*|}"
  echo "── $job"
  run_case "$job" "$prefix" "$classifier" md      false
  run_case "$job" "$prefix" "$classifier" code    true
  run_case "$job" "$prefix" "$classifier" shallow true "base_ref_resolves=no" "fatal:"
  run_case "$job" "$prefix" "$classifier" weak    true
  run_case "$job" "$prefix" "$classifier" mixed   true
  run_case "$job" "$prefix" "$classifier" big     true
  run_case "$job" "$prefix" "$classifier" symlink    true
  run_case "$job" "$prefix" "$classifier" execbit    true
  run_case "$job" "$prefix" "$classifier" modeflip   true
  run_case "$job" "$prefix" "$classifier" typechg    true
  run_case "$job" "$prefix" "$classifier" delete     true
  run_case "$job" "$prefix" "$classifier" transition true
done

total=$((PASS + FAIL))
if [ "$total" -lt 42 ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, want >=42\n' "$total" >&2
  exit 1
fi
echo
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
