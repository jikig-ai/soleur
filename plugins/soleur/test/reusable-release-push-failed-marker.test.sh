#!/usr/bin/env bash
# Guard 4 (#8211, plan 2026-11-09-feat-relay-hello-key-rotation-ghcr-push-diagnostics): the GHCR push-failure
# marker in .github/workflows/reusable-release.yml fires exactly on a failed image step, never leaks, and never
# changes the job's verdict.
#
# PROPERTY. When `docker_build` fails, the `push_failed_marker` step prints exactly one closed-grammar
# `SOLEUR_GHCR_PUSH_FAILED` line (stdout, one `::error::` annotation, one step-summary line in a code span) carrying
# the validated run attempt and one of four classes. `denial=` carries only text that matches the allowlist shape
# `denied: <code>: <reason>`; nothing is ever transformed into it (CTO ruling D2). The step never runs on success,
# never fails the job, cannot inject a workflow command, and no record field beyond the error message reaches any output. Diagnostics only:
# no retry (C1), no billing read (C3), no new permission.
#
# HOW. The workflow is parsed with PyYAML (never sliced by delimiter), the marker's `run:` body is executed under
# `bash --noprofile --norc -eo pipefail` (the runner's own invocation), and `docker` on PATH is a STRICT-ARGV stub: it
# accepts exactly `buildx history ls --filter status=error --format json` and
# `buildx history inspect <id> --format json`, and refuses anything else with exit 64 plus a refusal-log line.
#
# FIXTURE SHAPES were measured locally on 2026-11-10 with buildx 0.38.1 (the runner's version), a throwaway
# docker-container builder and a local registry:2 with htpasswd given wrong credentials (a real 401), over three
# failed builds:
#   - `history ls --format json` prints JSON LINES, NEWEST FIRST;
#   - its `ref` is `<builder>/<node>/<id>`, and `history inspect` resolves only the trailing `<id>` (the full ref
#     answers `no record found`, rc 1);
#   - the error text is `.Error.Message` of `history inspect <id> --format json`, with no `ERROR: ` prefix;
#     the step reads only `.ref` and `.Error.Message` from the record and prints nothing else from it.
# Every value below is synthesized (cq-test-fixtures-synthesized-only). The sentinel value is assembled from
# fragments so no contiguous token shape exists in this file.
#
# MUTATION MATRIX (Guard 4) -- run 2026-11-10 on a pristine copy of the workflow (and of this suite for row H),
# restored and diff-verified after each row. Control: unmutated, GREEN 280/280. Every row went RED (rc 1):
#   1    `if:` becomes `failure()` only                                  RED  S3
#   2    drop `continue-on-error: true`                                  RED  S4
#   3    move the step to just before the failure email (after zot)      RED  S2, S2b
#   4a   widen the allowlist reason class to `[^ ]+`                     RED  b9 (CR-injected `::warning::` reaches stdout)
#   4b   keep the whole message instead of its first line                RED  b8
#   4c   copy the remainder whenever the prefix matches                  RED  b2, b9, b10, b14 (19 rows)
#   4cap drop the 300-character cap                                      RED  b14
#   4d   also print the build record                                     RED  S8, token/stdout rows (54 rows)
#   4e   drop `--filter status=error` from `ls`                          RED  the stub refuses (64); refusal-log rows
#   4f   drop `timeout 10` from the `ls` read                            RED  S8b
#   4f2  drop `timeout-minutes: 1`                                       RED  S5
#   4g   drop DOCKER_BUILD_RECORD_UPLOAD / DOCKER_BUILD_SUMMARY           RED  S9a / S9b (one row each)
#   4h   also write denial to $GITHUB_OUTPUT                             RED  S10, output-exactness rows
#   4h2  format denial into the email                                    RED  S11, S13b
#   4i   restore "re-running this workflow is safe"                      RED  S12, S12b
#   4i2  drop the email sentence's class check                           RED  S13
#   5    rename the step id (the extractor finds no step)                RED  S1, S0, every behavioural row
#   6    read the OLDEST failed record instead of the newest             RED  b12
#   7    take RUN_ATTEMPT unvalidated                                    RED  b13 (grammar, output, attempt)
#   8    a `${{ }}` inside the run body                                  RED  S7, rc rows
#   H    the stub ignores its argv (alone, and together with 4e)         RED  H, H2
# Review round (PR #12536), 2026-11-10, in an allocated sandbox, pristine copies restored and cmp-verified after each
# row. Control: unmutated, GREEN 575/575 (before and after the matrix). Every row went RED:
#   R1   reason class `[^[:cntrl:]]+`                                    RED  b10n (30 rows)
#   R2   `^denied: [A-Za-z0-9_]+: [A-Za-z0-9_.]+$`                       RED  b10n (20 rows)
#   R3   cap `-le 299` / R4 `-le 301`                                    RED  b14b / b14c (3 rows each)
#   R5   check_eq `if true`, check `|| true`, check_absent `hit=0`,
#        `matches() { true; }`, `not() { true; }`, `in_order() { true; }` RED  helper self-test (rc 2, one row each)
#   R6   a second, unbounded docker call on the `ls` line                RED  S8, S8b, b4 call count
#   R7   VERSION / RUN_URL unvalidated; IMAGE widened to [^[:cntrl:]]    RED  b17v* / b17r* / b17i1
#   R8   email paragraph gated on the marker's class again               RED  S13
#   R9   email class fallback dropped                                    RED  S13b
#   R10  email deploy-arm clause unconditional again                     RED  S12b, S12c
#   R11  Slack sentence ignores RERUN_SCOPE                              RED  S16c
#   R12  a runbook class row renamed; runbook log read back to --log-failed  RED  S17b; b1 runbook rows
#   R13  a build-arg name printed to stderr                              RED  every case's name row (41 rows)
#   R14  the email names a runbook file that does not exist             RED  S18, S18b
#   R15  a step class outside the grammar                                RED  S17, S17b, behavioural rows
#   R16  the email sends the reader back to the Billing page             RED  S13d, S13e
# (R11's S16c was the dead `${RERUN_SCOPE:-this run}` pin; round 2 removed that fallback and re-used the id.)
# Review round 2, 2026-11-10, same method. Control: unmutated, GREEN 803/803 (idempotency suite 130/130). Every row
# went RED:
#   N1   check_absent scans only the first file; greps -x; greps -w      RED  helper self-test (rc 2, each)
#   N2   check_eq compares unquoted (glob)                               RED  helper self-test (rc 2)
#   N3   reason class `[a-z_./-]+` / `[a-z_-]+`; code class `[a-z_.-]+`  RED  b10n11-b10n16 (15 / 5 / 10 rows)
#   N4   `^` dropped from push_re / from denial_re                       RED  b10p / b10n8, b10n17
#   N5   image `[^[:space:]]`; run `^https?://`; attempt `*`; version
#        segment uncapped; record id `+`                                 RED  b17i3-4 / b17r4 / b13e / b17v4 / b15c
#   N6   a no-op `class="$class"`; `printf -v class`                     RED  S17c / S17, S17c
#   N7   Slack scope and run URL swapped; class and attempt swapped     RED  idempotency T7b (h) / (i)
#   N8   either re-run scope loses its push-event gate                   RED  S12b / S16 + idempotency env pin
#   N9   the dead Slack fallback restored; image line ungated            RED  S16c / S16e + idempotency (c), (l)
#   N10  email: not_push rules Billing out again; names a billing path   RED  S13g, S13h / S13f
#   N11  runbook: a gh run command without -R; the unmeasured row gone  RED  S17f / S17d
#
# Run: bash plugins/soleur/test/reusable-release-push-failed-marker.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"
RUNBOOK_REL="knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed.md"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing; this suite asserted nothing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing; this suite asserted nothing"; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "FAIL: timeout missing; this suite asserted nothing"; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML missing; this suite asserted nothing"; exit 1; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP_ROOT=$(mktemp -d -t push-failed-marker.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

passes=0
fails=0
cases=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Instrument self-test: drive both helpers before any real case, so a gutted helper cannot report a clean sweep.
# Reports with printf + exit, never through the helpers it guards.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0

# Every assertion counts itself in `cases` BEFORE its verdict, so a neutered pass()/fail() breaks the
# passes + fails == cases conservation check at the bottom.
check() { # <desc> <command...>: the verdict is the command's exit status
  local desc="$1"
  shift
  cases=$((cases + 1))
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
not() { ! "$@"; }
matches() { [[ "$1" =~ $2 ]]; }
in_order() { [[ "$1" -ge 0 && "$1" -lt "$2" ]]; }
check_eq() { # <desc> <got> <want>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 -> got '$2', want '$3'"; fi
}
check_absent() { # <desc> <needle> <file>...
  local desc="$1" needle="$2" f hit=0
  shift 2
  cases=$((cases + 1))
  for f in "$@"; do
    if grep -qF -- "$needle" "$f"; then hit=1; fi
  done
  if [[ "$hit" -eq 0 ]]; then pass "$desc"; else fail "$desc -> '$needle' found in output"; fi
}

# Known-negative self-test: every helper that owns a verdict is driven once with an input that MUST fail, and its
# failure counter must move by exactly one. An always-pass helper (`if true`, `matches() { true; }`, `hit=0`) would
# otherwise hold both the conservation check and the floor below. Counters are unwound afterwards; the verdict is
# reported with printf + exit, never through a helper under test.
st_passes=$passes st_fails=$fails st_cases=$cases
# check_absent's fixture is TWO files, and the needle sits mid-word in the SECOND: a helper that scans only the first
# file, or greps with -x (whole line) or -w (whole word), finds nothing and passes, so the self-test exits 2.
SELFTEST_FILE_A="$TMP_ROOT/selftest.clean"
SELFTEST_FILE_B="$TMP_ROOT/selftest.needle"
printf 'nothing to see\n' > "$SELFTEST_FILE_A"
printf 'before\nxxselftest-needleyy tail\n' > "$SELFTEST_FILE_B"
selftest_expect_fail() { # <helper name> <command...>: the command must raise fails by exactly one
  local name="$1" before="$fails"
  shift
  "$@" > /dev/null
  if [[ "$fails" -ne $((before + 1)) ]]; then
    printf 'FATAL: verdict helper %s did not fail on a known-false input (fails %s -> %s)\n' "$name" "$before" "$fails" >&2
    exit 2
  fi
}
selftest_expect_fail check_eq check_eq "selftest check_eq (expected FAIL)" "a" "b"
# A glob-matching check_eq (`== $3` unquoted) reads "a*" as a pattern and passes "ab".
selftest_expect_fail check_eq_glob check_eq "selftest check_eq is literal, not a glob (expected FAIL)" "ab" "a*"
selftest_expect_fail check check "selftest check (expected FAIL)" false
selftest_expect_fail check_absent check_absent "selftest check_absent (expected FAIL)" "selftest-needle" "$SELFTEST_FILE_A" "$SELFTEST_FILE_B"
selftest_expect_fail matches check "selftest matches (expected FAIL)" matches "x" '^y$'
selftest_expect_fail not check "selftest not (expected FAIL)" not true
selftest_expect_fail in_order check "selftest in_order (expected FAIL)" in_order 1 1
if [[ "$cases" -ne $((st_cases + 7)) || "$passes" -ne "$st_passes" ]]; then
  printf 'FATAL: helper self-test accounting broken (cases %s -> %s, passes %s -> %s)\n' "$st_cases" "$cases" "$st_passes" "$passes" >&2
  exit 2
fi
passes=$st_passes fails=$st_fails cases=$st_cases

echo "reusable-release-push-failed-marker.test.sh"

# ---------------------------------------------------------------------------------------------------------------
# Extraction (PyYAML). Emits one JSON document with every field the static rows read.
# ---------------------------------------------------------------------------------------------------------------
EXTRACT="$TMP_ROOT/extract.json"
python3 -I - "$WF" > "$EXTRACT" 2> "$TMP_ROOT/extract.err" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = doc["jobs"]["release"]
steps = job["steps"]
def idx(pred):
    return [i for i, s in enumerate(steps) if pred(s)]
marker = idx(lambda s: s.get("id") == "push_failed_marker")
build = idx(lambda s: s.get("id") == "docker_build")
email = idx(lambda s: s.get("name") == "Email notification (release FAILED)")
zot = idx(lambda s: s.get("id") == "zot_mirror")
slack = idx(lambda s: s.get("name") == "Post to Slack (release BLOCKED)")
m = steps[marker[0]] if len(marker) == 1 else {}
b = steps[build[0]] if len(build) == 1 else {}
e = steps[email[0]] if len(email) == 1 else {}
k = steps[slack[0]] if len(slack) == 1 else {}
out = {
    "marker_count": len(marker),
    "marker_index": marker[0] if marker else -1,
    "build_index": build[0] if build else -1,
    "zot_index": zot[0] if zot else -1,
    "if": m.get("if"),
    "continue_on_error": m.get("continue-on-error"),
    "timeout_minutes": m.get("timeout-minutes"),
    "shell": m.get("shell"),
    "env": m.get("env") or {},
    "run": m.get("run") or "",
    "build_env": b.get("env") or {},
    "email_if": e.get("if"),
    "email_body": (e.get("with") or {}).get("body") or "",
    "permissions": job.get("permissions"),
    "slack_rerun_scope": (k.get("env") or {}).get("RERUN_SCOPE"),
    "slack_run": k.get("run") or "",
}
print(json.dumps(out))
PY
if [[ ! -s "$EXTRACT" ]]; then
  echo "  FAIL: PyYAML extraction produced nothing:"
  sed 's/^/    /' "$TMP_ROOT/extract.err"
  echo "0 passed, 1 failed"
  exit 1
fi
x() { jq -r "$1" "$EXTRACT"; }

BODY="$TMP_ROOT/marker.sh"
x '.run' > "$BODY"

# --- S: static rows -----------------------------------------------------------------------------------------------
echo "S. static rows"
check_eq "S1 exactly one step has id push_failed_marker" "$(x '.marker_count')" "1"
check "S0 the extracted run body is non-empty" test -n "$(tr -d '[:space:]' < "$BODY")"
check_eq "S2 the marker sits immediately after docker_build" "$(x '.marker_index - .build_index')" "1"
check "S2b the marker precedes the zot mirror step" in_order "$(x '.marker_index')" "$(x '.zot_index')"
check_eq "S3 if: is exactly the failure-and-docker_build-failed gate" "$(x '.if')" "failure() && steps.docker_build.outcome == 'failure'"
check_eq "S4 continue-on-error is boolean true" "$(x '.continue_on_error')" "true"
check_eq "S5 timeout-minutes is 1" "$(x '.timeout_minutes')" "1"
check_eq "S5b no shell: override (the runner's bash -eo pipefail applies)" "$(x '.shell')" "null"
check_eq "S6 env keys are exactly IMAGE RUN_ATTEMPT RUN_URL VERSION" "$(x '.env | keys | join(" ")')" "IMAGE RUN_ATTEMPT RUN_URL VERSION"
check_eq "S6b RUN_ATTEMPT is github.run_attempt" "$(x '.env.RUN_ATTEMPT')" "\${{ github.run_attempt }}"
check_eq "S6c no env value reads a secret" "$(x '[.env[] | tostring | select(test("secrets\\."))] | length')" "0"
check "S7 no \${{ }} expression inside the run body" not grep -qF "\${{" "$BODY"
# Every docker INVOCATION (counted per occurrence, not per line: two calls can share a line) on a non-comment line
# runs through `timeout 10 docker buildx history`.
docker_calls=$(grep -vE '^[[:space:]]*#' "$BODY" | grep -oE '(^|[^A-Za-z_])docker[[:space:]]' | wc -l | tr -d ' ')
bounded_calls=$(grep -vE '^[[:space:]]*#' "$BODY" | grep -oE 'timeout 10 docker buildx history (ls|inspect) ' | wc -l | tr -d ' ')
check_eq "S8 exactly the two docker reads are invoked" "$docker_calls" "2"
check_eq "S8b every docker invocation is bounded by timeout 10" "$bounded_calls" "$docker_calls"
check_eq "S9a docker_build env DOCKER_BUILD_RECORD_UPLOAD is the string false" "$(x '.build_env.DOCKER_BUILD_RECORD_UPLOAD | tojson')" '"false"'
check_eq "S9b docker_build env DOCKER_BUILD_SUMMARY is the string false" "$(x '.build_env.DOCKER_BUILD_SUMMARY | tojson')" '"false"'
gho_denial=$(grep -vE '^[[:space:]]*#' "$BODY" | grep 'GITHUB_OUTPUT' | grep -c 'denial' || true)
check_eq "S10 no \$GITHUB_OUTPUT write names denial" "$gho_denial" "0"
EMAIL_BODY="$TMP_ROOT/email-body.txt"
x '.email_body' > "$EMAIL_BODY"
check "S11 the failure email never names denial" not grep -qi 'denial' "$EMAIL_BODY"
check "S12 the old 're-running this workflow is safe' wording is gone" not grep -qF 're-running this workflow is safe' "$EMAIL_BODY"
RERUN_ARMS="inputs.docker_image != '' && github.event_name == 'push' && 'this release run first, then, once it succeeds, on the deploy-arm (workflow_run) run for the same SHA' || 'this run'"
check "S12b the email names the deploy-arm run only for a push-started image release, after the release run, and forbids a fresh dispatch" grep -qF "so re-running is safe: 'Re-run failed jobs' on \${{ $RERUN_ARMS }}. A fresh 'Run workflow' dispatch is not safe" "$EMAIL_BODY"
check "S12c the email no longer names the deploy-arm run unconditionally" not grep -qF "(on both the release run and the deploy-arm run)" "$EMAIL_BODY"
check "S12d the email no longer names both runs without an order" not grep -qF "both the release run and the deploy-arm run" "$EMAIL_BODY"
check "S13 the email's image paragraph renders whenever docker_build failed (not on the marker's output)" grep -qF "\${{ steps.docker_build.outcome == 'failure' && format('<p>Image step failed (class <code>{0}</code>, attempt <code>{1}</code>)" "$EMAIL_BODY"
check "S13b the email paragraph formats only class and attempt, each with an unmeasured fallback" grep -qF "', steps.push_failed_marker.outputs.class || 'unmeasured — the marker step did not report', steps.push_failed_marker.outputs.attempt || 'unmeasured') || '' }}" "$EMAIL_BODY"
check "S13d the email points push_denied at the runbook's first-read section, by its heading" grep -qF "For <code>push_denied</code>, start at its section <code>First read, before anything else</code>" "$EMAIL_BODY"
check "S13d2 the section the email names is a heading of the runbook" grep -qxF "## First read, before anything else" "$REPO_ROOT/$RUNBOOK_REL"
check "S13f the email repeats no billing API command or org path" not grep -qE "gh api|settings/billing|jikig-ai" "$EMAIL_BODY"
check "S13g the email's not_push sentence does not rule Billing out, and sends a denied: log to the runbook" grep -qF "<code>not_push</code> means the error was not classified as an image-push failure; if the step log shows <code>denied:</code>, follow the runbook anyway." "$EMAIL_BODY"
check "S13h the email no longer asserts Billing is not the cause" not grep -qF "Billing is not the cause" "$EMAIL_BODY"
check "S13e the email no longer sends the reader to the Billing > Packages page" not grep -qF "check Billing &gt; Packages" "$EMAIL_BODY"
check_eq "S16 the Slack BLOCKED re-run scope is the email's, arm for arm" "$(x '.slack_rerun_scope')" "\${{ $RERUN_ARMS }}"
SLACK_RUN="$TMP_ROOT/slack-run.sh"
x '.slack_run' > "$SLACK_RUN"
# The rendered sentence (both arms, argument order) is pinned by executing this body in
# reusable-release-idempotency.test.sh T7b (h); these rows pin only its source.
check "S16b the Slack re-run sentence renders that scope" grep -qF 'To retry with the same version, use "Re-run failed jobs" on %s.' "$SLACK_RUN"
check "S16c the Slack sentence carries no dead fallback for the always-set scope" not grep -qF 'RERUN_SCOPE:-' "$SLACK_RUN"
check "S16d the old unconditional Slack re-run advice is gone" not grep -qF 'Re-run failed jobs on this run to retry' "$SLACK_RUN"
check "S16e the Slack image-step line is gated on IMAGE_CLASS" grep -qF 'if [ -n "${IMAGE_CLASS:-}" ]; then' "$SLACK_RUN"
check_eq "S13c the email step's if: is still failure()" "$(x '.email_if')" "failure()"
check_eq "S14 the release job's permissions are unchanged" "$(x '.permissions | tojson')" '{"contents":"write","packages":"write","id-token":"write"}'
check "S15 the runbook the marker points at exists" test -f "$REPO_ROOT/$RUNBOOK_REL"
check "S15b the run body names that runbook" grep -qF "runbook=\"$RUNBOOK_REL\"" "$BODY"
# Parity: the classes the step can assign are exactly the grammar's, and each has a row in the runbook's class table.
body_classes=$(grep -vE '^[[:space:]]*#' "$BODY" | grep -oE 'class="[a-z_]+"' | sed -E 's/^class="(.*)"$/\1/' | sort -u | tr '\n' ' ')
check_eq "S17 the step assigns exactly the four grammar classes" "$body_classes" "not_push push_denied push_other unknown "
for c in $body_classes; do
  check "S17b the runbook class table has a row for class $c" grep -qE "^\| \`$c\` \|" "$REPO_ROOT/$RUNBOOK_REL"
done
# Every occurrence of the word `class` in the body's code is one of five allowed forms; anything else (`class="$x"`,
# `class=$x`, `class+=`, `printf -v class`, `read class`, `declare class=...`) is refused, so only the four literals
# can ever be assigned.
class_forms=$(python3 -I - "$BODY" <<'PY'
import re, sys
code = "\n".join(l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if not re.match(r"\s*#", l))
allowed = [
    re.compile(r'(?<![^\s])class="(push_denied|push_other|not_push|unknown)"(?=\s|$)'),  # assignment of a literal
    re.compile(r'(?<=\$\{)class(?=\})'),                                                # ${class}
    re.compile(r'(?<="\$)class(?=")'),                                                  # "$class"
    re.compile(r'(?<= )class=(?=\$\{class\} )'),                                        # the marker line's field label
    re.compile(r"(?<=')class=(?=%s)"),                                                  # the $GITHUB_OUTPUT format
]
hits = list(re.finditer(r"\bclass\b", code))
bad = [code[m.start():m.start() + 24].replace("\n", " ") for m in hits if not any(a.match(code, m.start()) for a in allowed)]
print(f"total={len(hits)} bad={len(bad)}" + "".join(f" [{b}]" for b in bad))
PY
)
check "S17c every use of class in the body is a literal assignment or a read (got: $class_forms)" matches "$class_forms" '^total=[1-9][0-9]* bad=0$'
check "S17d the runbook class table has a row for unmeasured (the email's fallback)" grep -qE '^\| `unmeasured` \|' "$REPO_ROOT/$RUNBOOK_REL"
gh_run_lines=$(grep -cE '(^|[`[:space:]])gh run (list|view|rerun)( |$)' "$REPO_ROOT/$RUNBOOK_REL" || true)
gh_run_scoped=$(grep -E '(^|[`[:space:]])gh run (list|view|rerun)( |$)' "$REPO_ROOT/$RUNBOOK_REL" | grep -cE 'gh run (list|view|rerun) ([^ ]+ )?-R jikig-ai/soleur( |$)' || true)
check "S17e the runbook carries gh run commands (control)" test "$gh_run_lines" -ge 6
check_eq "S17f every gh run command in the runbook names the repo with -R" "$gh_run_scoped" "$gh_run_lines"
email_runbook=$(grep -oE '<code>[a-z0-9-]+\.md</code>' "$EMAIL_BODY" | sed -E 's#</?code>##g' | sort -u | tr '\n' ' ')
check_eq "S18 the email names exactly one runbook file, the marker's" "$email_runbook" "${RUNBOOK_REL##*/} "
check "S18b the runbook file the email names exists" test -f "$REPO_ROOT/$(dirname "$RUNBOOK_REL")/${email_runbook% }"

# ---------------------------------------------------------------------------------------------------------------
# Strict-argv docker stub.
# ---------------------------------------------------------------------------------------------------------------
STUB_DIR="$TMP_ROOT/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
if [[ $# -eq 7 && "$1" == buildx && "$2" == history && "$3" == ls && "$4" == --filter && "$5" == status=error \
      && "$6" == --format && "$7" == json ]]; then
  [[ "${STUB_LS_RC:-0}" == 0 ]] || { echo "ERROR: synthetic ls failure" >&2; exit "$STUB_LS_RC"; }
  [[ -f "$STUB_LS" ]] && cat "$STUB_LS"
  exit 0
fi
if [[ $# -eq 6 && "$1" == buildx && "$2" == history && "$3" == inspect && "$5" == --format && "$6" == json ]]; then
  # Measured: only the bare <id> resolves; a <builder>/<node>/<id> ref answers "no record found".
  if [[ "$4" =~ ^[a-z0-9]+$ && -f "$STUB_INSPECT_DIR/$4.json" ]]; then
    cat "$STUB_INSPECT_DIR/$4.json"
    exit 0
  fi
  echo "ERROR: no record found for ref \"$4\"" >&2
  exit 1
fi
printf '%s\n' "$*" >> "$STUB_REFUSED"
exit 64
STUB
chmod +x "$STUB_DIR/docker"

# Harness row H: the stub must refuse an argv it does not know (the `ls` call without --filter).
H_CALLS="$TMP_ROOT/h.calls"; H_REF="$TMP_ROOT/h.refused"; : > "$H_CALLS"; : > "$H_REF"
STUB_CALLS="$H_CALLS" STUB_REFUSED="$H_REF" STUB_LS="$TMP_ROOT/none" STUB_INSPECT_DIR="$TMP_ROOT/none" \
  "$STUB_DIR/docker" buildx history ls --format json > /dev/null 2>&1
h_rc=$?
check_eq "H the stub refuses an unknown argv with 64" "$h_rc" "64"
check "H2 the refusal is logged" test -s "$H_REF"

# Synthesized sentinel value, assembled from fragments (no contiguous token shape in this file).
SYNTH_TOKEN="sntr""ys_""SYNTHFIXTURE""0notareal""value0""4d""9e"
SYNTH_TOKEN_TAIL="SYNTHFIXTURE""0notareal"

# Fixture builders. ls_line <id> [name]; inspect_record <id> <message|__NOERROR__>.
ls_line() {
  jq -cn --arg id "$1" --arg name "${2:-web-platform}" \
    '{cached_steps:1,completed_at:"2026-11-10T09:55:03.038232123Z",completed_steps:5,
      created_at:"2026-11-10T09:55:02.709541801Z",name:$name,ref:("builder0/builder00/" + $id),
      status:"Error",total_steps:5}'
}
inspect_record() {
  local id="$1" msg="$2"
  jq -n --arg id "$id" --arg msg "$msg" --arg tok "$SYNTH_TOKEN" '
    {Name:"web-platform",Ref:$id,Context:"apps/web-platform",Dockerfile:"Dockerfile",
     StartedAt:"2026-11-10T09:55:02.709541801Z",CompletedAt:"2026-11-10T09:55:03.038232123Z",
     Duration:328690322,Status:"failed",NumCompletedSteps:5,NumTotalSteps:5,NumCachedSteps:1,
     BuildArgs:[{Name:"BUILD_VERSION",Value:"0.402.0"},{Name:"SENTRY_AUTH_TOKEN",Value:$tok}],
     Attachments:[]}
    + (if $msg == "__NOERROR__" then {} else
        {Error:{Code:2,Message:$msg,Stack:("synthetic stack\nbuild-arg echo SENTRY_AUTH_TOKEN=" + $tok)}} end)'
}

GRAMMAR='^SOLEUR_GHCR_PUSH_FAILED image=[^ ]+ version=[^ ]+ attempt=([1-9][0-9]*|invalid) run=[^ ]+ class=(push_denied|push_other|not_push|unknown) denial=(denied: [a-z_]+: [a-z_]+|withheld|see-step-log) runbook=knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed\.md$'

STUB_INVOCATIONS=0
# run_case <name>: runs the marker body with the fixture files under $TMP_ROOT/<name>/ and leaves
# rc / stdout / summary / output / calls / refused in that directory. Env knobs: CASE_LS_RC, CASE_ATTEMPT,
# CASE_IMAGE, CASE_VERSION, CASE_RUN_URL. `env -i` leaves the POSIX locale, so `${#remainder}` counts bytes here; the
# runner (C.UTF-8) counts characters. The allowlist is ASCII-only, so the two agree on every value it can admit.
run_case() {
  local d="$TMP_ROOT/$1"
  mkdir -p "$d/inspect"
  : > "$d/calls"; : > "$d/refused"; : > "$d/summary"; : > "$d/output"
  [[ -f "$d/ls" ]] || : > "$d/ls"
  env -i PATH="$STUB_DIR:$PATH" HOME="$d" \
    STUB_CALLS="$d/calls" STUB_REFUSED="$d/refused" STUB_LS="$d/ls" STUB_INSPECT_DIR="$d/inspect" \
    STUB_LS_RC="${CASE_LS_RC:-0}" \
    IMAGE="${CASE_IMAGE-ghcr.io/jikig-ai/soleur-web-platform}" VERSION="${CASE_VERSION-0.402.0}" \
    RUN_ATTEMPT="${CASE_ATTEMPT-1}" \
    RUN_URL="${CASE_RUN_URL-https://github.com/jikig-ai/soleur/actions/runs/123456789/attempts/1}" \
    GITHUB_OUTPUT="$d/output" GITHUB_STEP_SUMMARY="$d/summary" \
    bash --noprofile --norc -eo pipefail "$BODY" > "$d/stdout" 2> "$d/stderr"
  echo $? > "$d/rc"
  if [[ -s "$d/calls" ]]; then STUB_INVOCATIONS=$((STUB_INVOCATIONS + 1)); fi
}
# one_record <name> <message>: a single failed record whose error is <message>.
one_record() {
  local d="$TMP_ROOT/$1"
  mkdir -p "$d/inspect"
  ls_line "a1b2c3d4e5f6g7h8i9j0k1l2m" > "$d/ls"
  inspect_record "a1b2c3d4e5f6g7h8i9j0k1l2m" "$2" > "$d/inspect/a1b2c3d4e5f6g7h8i9j0k1l2m.json"
}
marker_line() { grep -E '^SOLEUR_GHCR_PUSH_FAILED ' "$TMP_ROOT/$1/stdout" | head -n 1; }
class_of() { marker_line "$1" | sed -nE 's/.* class=([a-z_]+) denial=.*/\1/p'; }
denial_of() { marker_line "$1" | sed -nE 's/.* denial=(.*) runbook=.*/\1/p'; }
attempt_of() { marker_line "$1" | sed -nE 's/.* attempt=([^ ]+) run=.*/\1/p'; }
field_of() { marker_line "$1" | sed -nE "s/^SOLEUR_GHCR_PUSH_FAILED (.* )?$2=([^ ]*) .*/\\2/p"; } # <case> <image|version|run>

# expect_case <name> <class> <denial> <attempt>: the common rows every behavioural case must hold.
expect_case() {
  local n="$1" c="$2" den="$3" att="${4:-1}" d="$TMP_ROOT/$1" line
  line="$(marker_line "$n")"
  check_eq "$n: rc 0 (never fails the job)" "$(cat "$d/rc")" "0"
  check_eq "$n: class" "$(class_of "$n")" "$c"
  check_eq "$n: denial" "$(denial_of "$n")" "$den"
  check "$n: the line matches the full closed grammar" matches "$line" "$GRAMMAR"
  check_eq "$n: exactly one plain marker line on stdout" "$(grep -cE '^SOLEUR_GHCR_PUSH_FAILED ' "$d/stdout")" "1"
  check_eq "$n: exactly one ::error:: annotation, carrying the same line" "$(grep -cxF "::error::$line" "$d/stdout")" "1"
  check_eq "$n: stdout holds nothing else" "$(wc -l < "$d/stdout" | tr -d ' ')" "2"
  check_eq "$n: the summary is the line in a code span" "$(cat "$d/summary")" "\`$line\`"
  check_eq "$n: \$GITHUB_OUTPUT holds only class and attempt" "$(cat "$d/output")" "class=$c"$'\n'"attempt=$att"
  check_absent "$n: no build-arg token value reaches any output" "$SYNTH_TOKEN_TAIL" "$d/stdout" "$d/stderr" "$d/summary" "$d/output"
  check_absent "$n: no build-arg name reaches any output" "SENTRY_AUTH_TOKEN" "$d/stdout" "$d/stderr" "$d/summary" "$d/output"
  check_eq "$n: the stub refused nothing" "$(wc -c < "$d/refused" | tr -d ' ')" "0"
}

echo "B. behavioural rows"

# B1 — the canonical v0.402.0 denial text.
one_record b1 "failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: permission_denied: write_package"
run_case b1
expect_case b1 push_denied "denied: permission_denied: write_package"
check_eq "b1: inspect was called with the bare record id" "$(grep -c '^buildx history inspect a1b2c3d4e5f6g7h8i9j0k1l2m --format json$' "$TMP_ROOT/b1/calls")" "1"
# Positive controls for the field validation: valid values print verbatim (the negatives are B17).
check_eq "b1: image is printed verbatim" "$(field_of b1 image)" "ghcr.io/jikig-ai/soleur-web-platform"
check_eq "b1: version is printed verbatim" "$(field_of b1 version)" "0.402.0"
check_eq "b1: run is printed verbatim" "$(field_of b1 run)" "https://github.com/jikig-ai/soleur/actions/runs/123456789/attempts/1"
# The runbook's log read, applied to a synthetic log holding the step's own script (Actions prints it) and its output:
# it keeps exactly the two emitted marker lines and drops the script's copy of the prefix.
RUNBOOK_GREP="gh run view <run-id> -R jikig-ai/soleur --log | grep -F 'SOLEUR_GHCR_PUSH_FAILED image=' | grep -vF '\${image}'"
check "b1: the runbook documents the full-log marker read" grep -qF "$RUNBOOK_GREP" "$REPO_ROOT/$RUNBOOK_REL"
check "b1: the runbook no longer documents the --log-failed read" not grep -qF -- "--log-failed | grep" "$REPO_ROOT/$RUNBOOK_REL"
cat "$BODY" "$TMP_ROOT/b1/stdout" > "$TMP_ROOT/b1/synthetic.log"
grep -F 'SOLEUR_GHCR_PUSH_FAILED image=' "$TMP_ROOT/b1/synthetic.log" | grep -vF '${image}' > "$TMP_ROOT/b1/log-read" || true
check_eq "b1: the runbook's log read yields exactly the two emitted marker lines" "$(cat "$TMP_ROOT/b1/log-read")" "$(cat "$TMP_ROOT/b1/stdout")"
check "b1: the step's script really carries the prefix the second grep drops (control)" grep -qF 'SOLEUR_GHCR_PUSH_FAILED image=${image}' "$BODY"

# B1b — the same denial with the CLI's `ERROR: ` prefix still classifies.
one_record b1b "ERROR: failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: permission_denied: write_package"
run_case b1b
expect_case b1b push_denied "denied: permission_denied: write_package"

# B2 — the measured registry:2 401 text (wrong htpasswd credentials): a push failure whose text is withheld.
one_record b2 "failed to push localhost:5055/measure/app:v3: unexpected status from HEAD request to http://localhost:5055/v2/measure/app/blobs/sha256:c2fb277c387763b1841804e113ad7a24163f0472f462c3ce41151ce41cd116cb: 401 Unauthorized"
run_case b2
expect_case b2 push_other withheld
check_absent "b2: the withheld registry text is absent" "401 Unauthorized" "$TMP_ROOT/b2/stdout" "$TMP_ROOT/b2/summary"

# B3 — must-PASS: a failed RUN step is not an image-push failure (measured text).
one_record b3 'process "/bin/sh -c npm run build" did not complete successfully: exit code: 1'
run_case b3
expect_case b3 not_push see-step-log

# B4 — must-PASS: the history read fails.
mkdir -p "$TMP_ROOT/b4"
CASE_LS_RC=1 run_case b4
expect_case b4 unknown see-step-log
check_eq "b4: exactly one docker call (no unbounded fallback read)" "$(wc -l < "$TMP_ROOT/b4/calls" | tr -d ' ')" "1"

# B5 — the no-build-ref fallback: `ls` returns nothing (measured: rc 0, empty output).
mkdir -p "$TMP_ROOT/b5"
run_case b5
expect_case b5 unknown see-step-log
check_eq "b5: no inspect is attempted without a ref" "$(grep -c 'inspect' "$TMP_ROOT/b5/calls")" "0"

# B6 — the record named by `ls` cannot be inspected.
mkdir -p "$TMP_ROOT/b6"
ls_line "zz9y8x7w6v5u4t3s2r1q0p9o8" > "$TMP_ROOT/b6/ls"
run_case b6
expect_case b6 unknown see-step-log

# B7 — the record carries no Error field.
one_record b7 "__NOERROR__"
run_case b7
expect_case b7 unknown see-step-log

# B8 — LF injection: only the first line of the error is read.
one_record b8 $'failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: permission_denied: write_package\n::warning::injected'
run_case b8
expect_case b8 push_denied "denied: permission_denied: write_package"
check_absent "b8: the second line never reaches any output" "::warning::" "$TMP_ROOT/b8/stdout" "$TMP_ROOT/b8/summary" "$TMP_ROOT/b8/output"
one_record b8b $'process "/bin/sh -c x" did not complete successfully: exit code: 1\nfailed to push r:v1: denied: permission_denied: write_package'
run_case b8b
expect_case b8b not_push see-step-log

# B9 — CR injection on the first line: the allowlist refuses it, nothing is transformed.
one_record b9 $'failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: permission_denied: write_package\r::warning::injected'
run_case b9
expect_case b9 push_other withheld
check_absent "b9: the CR-injected command never reaches any output" "::warning::" "$TMP_ROOT/b9/stdout" "$TMP_ROOT/b9/summary"
check_absent "b9: no CR reaches stdout" $'\r' "$TMP_ROOT/b9/stdout" "$TMP_ROOT/b9/summary"

# B10 — the prefix matches but the remainder is not the allowlist shape: withheld, never copied.
one_record b10 "failed to push r:v1: unexpected status 500 https://x/y?token=abc"
run_case b10
expect_case b10 push_other withheld
check_absent "b10: the remainder is not copied" "token=abc" "$TMP_ROOT/b10/stdout" "$TMP_ROOT/b10/summary"

# B10n — near misses: each remainder starts like an allowed denial but sits just outside `denied: [a-z_]+: [a-z_]+`.
# Each must give push_other/withheld and its remainder must not be copied. Kills a widened reason class
# (`[^[:cntrl:]]+`, `[A-Za-z0-9_.]+`) that the CR fixture alone does not reach.
near_misses=(
  "denied: Permission_Denied: write_package"
  "denied: permission_denied: Write_Package"
  "denied: permission_denied: write_package2"
  "denied: permission_denied2: write_package"
  "denied: permission_denied: write package"
  "denied: permission_denied: The token provided does not match expected scopes."
  "denied: permission_denied: https://x/y?token=abc"
  "denied: permission_denied: write_package: extra"
  "denied:permission_denied: write_package"
  "denied: permission_denied:write_package"
  "denied: permission_denied: write-package"
  "denied: permission-denied: write_package"
  "denied: permission_denied: ghcr.io/x"
  "denied: permission_denied: a.b"
  "denied: permission.denied: write_package"
  "denied: a/b: c"
  "xdenied: permission_denied: write_package"
)
nm=0
for rem in "${near_misses[@]}"; do
  nm=$((nm + 1))
  one_record "b10n$nm" "failed to push r:v1: $rem"
  run_case "b10n$nm"
  expect_case "b10n$nm" push_other withheld
  check_absent "b10n$nm: the near-miss remainder '$rem' is not copied" "$rem" "$TMP_ROOT/b10n$nm/stdout" "$TMP_ROOT/b10n$nm/summary"
done
check_eq "b10n: every near-miss fixture ran" "$nm" "17"

# B10p — the push prefix mid-message is not a push failure: push_re is anchored at the start (kills a dropped `^`).
one_record b10p "step x failed to push r:v1: denied: permission_denied: write_package"
run_case b10p
expect_case b10p not_push see-step-log

# B11 — the build-arg token fixture: the record carries a synthesized SENTRY_AUTH_TOKEN build-arg and stack echo.
one_record b11 "failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: permission_denied: write_package"
check "b11: the fixture really carries the token (control)" grep -qF "$SYNTH_TOKEN_TAIL" "$TMP_ROOT/b11/inspect/a1b2c3d4e5f6g7h8i9j0k1l2m.json"
run_case b11
expect_case b11 push_denied "denied: permission_denied: write_package"

# B12 — order (measured newest first): the newest failed record is read, not an older one after it.
mkdir -p "$TMP_ROOT/b12/inspect"
{ ls_line "newest0000000000000000000a"; ls_line "older00000000000000000000b"; } > "$TMP_ROOT/b12/ls"
inspect_record "newest0000000000000000000a" "failed to push r:v1: denied: permission_denied: write_package" > "$TMP_ROOT/b12/inspect/newest0000000000000000000a.json"
inspect_record "older00000000000000000000b" 'process "/bin/sh -c x" did not complete successfully: exit code: 1' > "$TMP_ROOT/b12/inspect/older00000000000000000000b.json"
run_case b12
expect_case b12 push_denied "denied: permission_denied: write_package"

# B13 — attempt is validated.
one_record b13 "failed to push r:v1: denied: permission_denied: write_package"
CASE_ATTEMPT='1;x' run_case b13
expect_case b13 push_denied "denied: permission_denied: write_package" invalid
one_record b13b "failed to push r:v1: denied: permission_denied: write_package"
CASE_ATTEMPT='2' run_case b13b
expect_case b13b push_denied "denied: permission_denied: write_package" 2
one_record b13c "failed to push r:v1: denied: permission_denied: write_package"
CASE_ATTEMPT='0' run_case b13c
expect_case b13c push_denied "denied: permission_denied: write_package" invalid
# The length cap on both sides: six digits are kept, seven print invalid (kills `{0,5}` widened to `*`).
one_record b13d "failed to push r:v1: denied: permission_denied: write_package"
CASE_ATTEMPT='123456' run_case b13d
expect_case b13d push_denied "denied: permission_denied: write_package" 123456
one_record b13e "failed to push r:v1: denied: permission_denied: write_package"
CASE_ATTEMPT='1234567' run_case b13e
expect_case b13e push_denied "denied: permission_denied: write_package" invalid

# B14 — the 300-char cap: an allowlist-shaped remainder longer than 300 characters is withheld.
long_reason="$(printf 'a%.0s' $(seq 1 300))"
one_record b14 "failed to push r:v1: denied: permission_denied: $long_reason"
run_case b14
expect_case b14 push_other withheld

# B14b — the cap boundary on both sides: a remainder of exactly 300 characters is copied, 301 is withheld.
cap_prefix="denied: permission_denied: "
rem300="${cap_prefix}$(printf 'b%.0s' $(seq 1 $((300 - ${#cap_prefix}))))"
rem301="${rem300}b"
check_eq "b14b: the 300 fixture is exactly 300 characters (control)" "${#rem300}" "300"
check_eq "b14b: the 301 fixture is exactly 301 characters (control)" "${#rem301}" "301"
one_record b14b "failed to push r:v1: $rem300"
run_case b14b
expect_case b14b push_denied "$rem300"
one_record b14c "failed to push r:v1: $rem301"
run_case b14c
expect_case b14c push_other withheld

# B14d — a second allowed denial of a different shape (both segments differ from the v0.402.0 text).
one_record b14d "failed to push ghcr.io/jikig-ai/soleur-web-platform:v0.402.0: denied: insufficient_scope: read_package"
run_case b14d
expect_case b14d push_denied "denied: insufficient_scope: read_package"

# B15 — a ref whose id is not the measured shape is never passed to inspect.
mkdir -p "$TMP_ROOT/b15"
jq -cn '{ref:"builder0/builder00/BAD;ID $(x)",status:"Error"}' > "$TMP_ROOT/b15/ls"
run_case b15
expect_case b15 unknown see-step-log
check_eq "b15: no inspect is attempted for a malformed id" "$(grep -c 'inspect' "$TMP_ROOT/b15/calls")" "0"

# B15b — the record id length cap on both sides: 64 characters is inspected, 65 is not (kills `{1,64}` widened to `+`).
id64="$(printf 'c%.0s' $(seq 1 64))"
id65="${id64}c"
check_eq "b15b: the 64 id is exactly 64 characters (control)" "${#id64}" "64"
for pair in "b15b:$id64:push_denied" "b15c:$id65:unknown"; do
  IFS=: read -r n rid want <<< "$pair"
  mkdir -p "$TMP_ROOT/$n/inspect"
  ls_line "$rid" > "$TMP_ROOT/$n/ls"
  inspect_record "$rid" "failed to push r:v1: denied: permission_denied: write_package" > "$TMP_ROOT/$n/inspect/$rid.json"
  run_case "$n"
  if [[ "$want" == push_denied ]]; then
    expect_case "$n" push_denied "denied: permission_denied: write_package"
  else
    expect_case "$n" unknown see-step-log
  fi
done
check_eq "b15c: no inspect is attempted for a 65-character id" "$(grep -c 'inspect' "$TMP_ROOT/b15c/calls")" "0"

# B16 — an injected IMAGE is replaced, never printed.
one_record b16 "failed to push r:v1: denied: permission_denied: write_package"
CASE_IMAGE=$'ghcr.io/x\n::warning::injected' run_case b16
expect_case b16 push_denied "denied: permission_denied: write_package"
check_eq "b16: image=invalid" "$(marker_line b16 | sed -nE 's/^SOLEUR_GHCR_PUSH_FAILED image=([^ ]+) .*/\1/p')" "invalid"
check_absent "b16: the injected line never reaches any output" "::warning::" "$TMP_ROOT/b16/stdout" "$TMP_ROOT/b16/summary"

# B17 — every other printed field is validated too: a value outside its shape prints `invalid`, never itself.
# b17_row <name> <field> <knob> <value>: runs one case with that knob set and expects <field>=invalid.
b17_row() {
  local n="$1" field="$2" knob="$3" val="$4"
  one_record "$n" "failed to push r:v1: denied: permission_denied: write_package"
  case "$knob" in
    IMAGE) CASE_IMAGE="$val" run_case "$n" ;;
    VERSION) CASE_VERSION="$val" run_case "$n" ;;
    RUN_URL) CASE_RUN_URL="$val" run_case "$n" ;;
  esac
  expect_case "$n" push_denied "denied: permission_denied: write_package"
  check_eq "$n: $field='$val' prints invalid" "$(field_of "$n" "$field")" "invalid"
}
b17_row b17v1 version VERSION "0.402.0 ::warning::x"
b17_row b17v2 version VERSION "v0.402.0"
b17_row b17v3 version VERSION "0.402"
b17_row b17r1 run RUN_URL "javascript:x"
b17_row b17r2 run RUN_URL "https://github.com/x y"
b17_row b17r3 run RUN_URL "https://github.com/x?token=abc"
b17_row b17i1 image IMAGE "ghcr.io/x y"
b17_row b17i2 image IMAGE "GHCR.io/jikig-ai/soleur-web-platform"
# Second axis for each field: values with no space that sit outside the class (kill a widened `[^[:space:]]`,
# `^https?://`, an uncapped version segment).
b17_row b17i3 image IMAGE "ghcr.io/x?y"
b17_row b17i4 image IMAGE $'ghcr.io/x\x1by'
b17_row b17i5 image IMAGE $'ghcr.io/x\ty'
b17_row b17r4 run RUN_URL "http://github.com/jikig-ai/soleur/actions/runs/1"
b17_row b17v4 version VERSION "1234567.0.0"

# Row 5 (own dispatch): the stub was actually invoked by the body.
check "R5 the docker stub was invoked by the run body" test "$STUB_INVOCATIONS" -ge 10

# ---------------------------------------------------------------------------------------------------------------
# Accounting conservation, then the anti-vacuity floor. Both report through printf + exit, never through the
# pass()/fail() pair they backstop.
# ---------------------------------------------------------------------------------------------------------------
if [[ $((passes - 1 + fails)) -ne "$cases" ]]; then
  printf 'FATAL: accounting broken — passes(%s)-1 + fails(%s) != cases(%s); a verdict helper is not dispatching\n' \
    "$passes" "$fails" "$cases" >&2
  exit 1
fi
# SELFTEST_PASSES is a LITERAL here, not a variable bound after the self-test: guard-vacuity-floor.test.sh slices
# the floor plus its CONTIGUOUS assignments into a mutant, and a binding far above is unbound there. The self-test
# above asserts passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_PASSES=803
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_PASSES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' "$REAL_PASSES" "$MIN_PASSES" >&2
  exit 1
fi

echo "=== Results: $REAL_PASSES passed, $fails failed ($cases assertions) ==="
[[ "$fails" -eq 0 ]] || exit 1
