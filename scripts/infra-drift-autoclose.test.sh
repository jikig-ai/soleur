#!/usr/bin/env bash
# Tests for infra-drift-autoclose.sh.
#
# The script decides whether the apply-deploy-pipeline-fix workflow may auto-close an open
# `infra-drift` issue with "Server state was re-aligned with HEAD". That sentence is a claim
# about the whole stack; the workflow only plans five -target terraform_data resources, while
# the issue is filed from an UNTARGETED plan. So the properties under test are about EVIDENCE
# (readable, complete, no pending hcloud_server action) and about the close CHOKEPOINT, not
# about "does it call gh".
#
# Fixtures under scripts/fixtures/infra-drift-autoclose/ are SYNTHESIZED from the shapes of the
# real issue bodies and comments, never their text, ids or tokens. CRLF variants are derived at
# run time (a committed CRLF file can be silently normalized by git).
#
# Set DRIFT_NO_BATTERY=1 to run only the product assertions (the mutation battery and the harness
# rows re-invoke this file that way, so they do not recurse).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="${DRIFT_TEST_HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$HERE/infra-drift-autoclose.sh"
FIX="${DRIFT_FIXTURE_DIR:-$HERE/fixtures/infra-drift-autoclose}"
WORKFLOW="$REPO/.github/workflows/apply-deploy-pipeline-fix.yml"
STEP_NAME="Auto-close any open drift issues for this stack"
PASS=0; FAIL=0; CASES=0
FAILURES=()

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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

# One owning sandbox root and one EXIT trap (ADR-129 rule c). mk_sandbox is called in a command
# substitution, so it must not append to an array (the append would land in the subshell).
SANDBOX_ROOT="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup_tmpdirs() { [[ -n "${SANDBOX_ROOT:-}" && -d "$SANDBOX_ROOT" ]] && rm -rf "$SANDBOX_ROOT"; return 0; }
trap cleanup_tmpdirs EXIT INT TERM
mk_sandbox() { local d; d=$(mktemp -d "$SANDBOX_ROOT/sb.XXXXXX") || return 1; printf '%s' "$d"; }

# CASES is incremented at every verdict CALL SITE and never inside ok()/bad(): a counter that
# lives inside the verdict helpers moves with the verdict, so neutering bad() would drop the row
# and its count together. Never increment inside $( ) -- a subshell discards it.
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

echo "infra-drift-autoclose.test.sh"

# --- fixtures must exist and be non-empty (a missing fixture must not read as a skipped row) ---
for f in replacement-present.body.md replacement-escaped-only.body.md truncated-cut.body.md \
         truncated-title.body.md truncated-title-escaped.body.md clean.body.md \
         comment-clean.md comment-replacement.md comment-truncated.md; do
  CASES=$((CASES + 1))
  if [[ -s "$FIX/$f" ]]; then ok "fixture present and non-empty: $f"; else bad "fixture missing or empty: $f"; fi
done

CASES=$((CASES + 1))
if [[ -f "$SCRIPT" ]]; then ok "the script under test exists"; else bad "the script under test does not exist: $SCRIPT"; fi

# ---------------------------------------------------------------------------------------------
# Envelope builders. The classifier reads {"body": <string>, "comments": [<string>, ...]}.
# ---------------------------------------------------------------------------------------------
env_with_comments() {  # <bodyfile> [commentfile...]
  local b="$1" j c
  shift
  j=$(jq -n --rawfile b "$b" '{body:$b,comments:[]}') || return 1
  for c in "$@"; do
    j=$(jq --rawfile c "$c" '.comments += [$c]' <<<"$j") || return 1
  done
  printf '%s' "$j"
}
env_text() {  # <text> -> envelope with that body
  jq -n --arg b "$1" '{body:$b,comments:[]}'
}
# A minimal COMPLETE plan carrying exactly one resource-header line.
mini() {
  printf '<details><summary>Plan output</summary>\n\n```\n%s\n\nPlan: 1 to add, 0 to change, 1 to destroy.\n\nNote: You didn'"'"'t use the -out option to save this plan, so Terraform can'"'"'t\n```\n\n</details>\n' "$1"
}
mini_no_footer() {  # same but WITHOUT either terminator
  printf '<details><summary>Plan output</summary>\n\n```\n%s\n  ~ example = "a" -> "b"\n```\n\n</details>\n' "$1"
}

SBX="$(mk_sandbox)"
assert_fixture_dir "$SBX"
derive_fixtures() {
  assert_fixture_dir "$SBX"
  sed 's/$/\r/' "$FIX/clean.body.md" > "$SBX/clean-crlf.body.md"
  sed 's/$/\r/' "$FIX/replacement-present.body.md" > "$SBX/replacement-crlf.body.md"
  sed 's/&quot;/\&amp;quot;/g' "$FIX/replacement-escaped-only.body.md" > "$SBX/replacement-double-escaped.body.md"
  printf 'Thanks, I will look at this tomorrow.\n' > "$SBX/comment-human.md"
}
derive_fixtures

build_env() {  # <case-name>
  case "$1" in
    replacement-present)        env_with_comments "$FIX/replacement-present.body.md" ;;
    replacement-escaped-only)   env_with_comments "$FIX/replacement-escaped-only.body.md" ;;
    replacement-double-escaped) env_with_comments "$SBX/replacement-double-escaped.body.md" ;;
    replacement-crlf)           env_with_comments "$SBX/replacement-crlf.body.md" ;;
    truncated-cut)              env_with_comments "$FIX/truncated-cut.body.md" ;;
    truncated-title)            env_with_comments "$FIX/truncated-title.body.md" ;;
    truncated-title-escaped)    env_with_comments "$FIX/truncated-title-escaped.body.md" ;;
    clean)                      env_with_comments "$FIX/clean.body.md" ;;
    clean-crlf)                 env_with_comments "$SBX/clean-crlf.body.md" ;;
    empty-body)                 printf '{"body":"","comments":[]}' ;;
    whitespace-body)            printf '{"body":"  \\n  ","comments":[]}' ;;
    null-body)                  printf '{"body":null,"comments":[]}' ;;
    no-plan-block)              env_text 'A human wrote this issue and pasted no plan.' ;;
    malformed-json)             printf 'not json' ;;
    wrong-type-body)            printf '{"body":5,"comments":[]}' ;;
    empty-stdin)                printf '' ;;
    r1-indexed)                 env_text "$(mini '  # hcloud_server.web["web-2"] must be replaced')" ;;
    r1-tainted)                 env_text "$(mini '  # hcloud_server.web["web-2"] is tainted, so must be replaced')" ;;
    r1-as-requested)            env_text "$(mini '  # hcloud_server.web will be replaced, as requested')" ;;
    r1-destroyed)               env_text "$(mini '  # hcloud_server.web will be destroyed')" ;;
    r1-created)                 env_text "$(mini '  # hcloud_server.web will be created')" ;;
    r1-module)                  env_text "$(mini '  # module.example.hcloud_server.web["web-2"] must be replaced')" ;;
    r2-only)                    env_text "$(mini '-/+ resource "hcloud_server" "web" {')" ;;
    near-miss-network)          env_text "$(mini '  # hcloud_server_network.x must be replaced')" ;;
    inplace-update)             env_text "$(mini '  # hcloud_server.web["web-1"] will be updated in-place')" ;;
    refresh-line)               env_text "$(mini 'hcloud_server.web["web-1"]: Refreshing state... [id=2222222]')" ;;
    footer-only-complete)       env_text "$(printf '<details><summary>Plan output</summary>\n\n```\n  ~ example = "a" -> "b"\n\nNote: You didn'"'"'t use the -out option to save this plan, so Terraform can'"'"'t\n```\n\n</details>\n')" ;;
    no-terminator)              env_text "$(mini_no_footer '  # terraform_data.example must be replaced')" ;;
    c-clean-then-replacement)   env_with_comments "$FIX/clean.body.md" "$FIX/comment-replacement.md" ;;
    c-clean-then-truncated)     env_with_comments "$FIX/clean.body.md" "$FIX/comment-truncated.md" ;;
    c-clean-then-clean)         env_with_comments "$FIX/clean.body.md" "$FIX/comment-clean.md" ;;
    c-replacement-then-clean)   env_with_comments "$FIX/replacement-present.body.md" "$FIX/comment-clean.md" ;;
    c-replacement-then-trunc)   env_with_comments "$FIX/replacement-present.body.md" "$FIX/comment-truncated.md" ;;
    c-clean-then-human)         env_with_comments "$FIX/clean.body.md" "$SBX/comment-human.md" ;;
    c-clean-then-replacement-then-human) env_with_comments "$FIX/clean.body.md" "$FIX/comment-replacement.md" "$SBX/comment-human.md" ;;
    *) echo "unknown case $1" >&2; return 1 ;;
  esac
}

declare -A EXPECT=(
  [replacement-present]=skip:hcloud-server-replacement
  [replacement-escaped-only]=skip:hcloud-server-replacement
  [replacement-double-escaped]=skip:hcloud-server-replacement
  [replacement-crlf]=skip:hcloud-server-replacement
  [truncated-cut]=skip:plan-incomplete
  [truncated-title]=skip:plan-truncated-marker
  [truncated-title-escaped]=skip:plan-truncated-marker
  [clean]=close
  [clean-crlf]=close
  [empty-body]=skip:empty-body
  [whitespace-body]=skip:empty-body
  [null-body]=skip:empty-body
  [no-plan-block]=skip:no-plan-block
  [malformed-json]=skip:unparseable
  [wrong-type-body]=skip:unparseable
  [empty-stdin]=skip:empty-body
  [r1-indexed]=skip:hcloud-server-replacement
  [r1-tainted]=skip:hcloud-server-replacement
  [r1-as-requested]=skip:hcloud-server-replacement
  [r1-destroyed]=skip:hcloud-server-replacement
  [r1-created]=skip:hcloud-server-replacement
  [r1-module]=skip:hcloud-server-replacement
  [r2-only]=skip:hcloud-server-replacement
  [near-miss-network]=close
  [inplace-update]=close
  [refresh-line]=close
  [footer-only-complete]=close
  [no-terminator]=skip:plan-incomplete
  [c-clean-then-replacement]=skip:hcloud-server-replacement
  [c-clean-then-truncated]=skip:plan-incomplete
  [c-clean-then-clean]=close
  [c-replacement-then-clean]=close
  [c-replacement-then-trunc]=skip:plan-incomplete
  [c-clean-then-human]=close
  [c-clean-then-replacement-then-human]=skip:hcloud-server-replacement
)
CASE_ORDER=(
  replacement-present replacement-escaped-only replacement-double-escaped replacement-crlf
  truncated-cut truncated-title truncated-title-escaped clean clean-crlf
  empty-body whitespace-body null-body no-plan-block malformed-json wrong-type-body empty-stdin
  r1-indexed r1-tainted r1-as-requested r1-destroyed r1-created r1-module r2-only
  near-miss-network inplace-update refresh-line footer-only-complete no-terminator
  c-clean-then-replacement c-clean-then-truncated c-clean-then-clean c-replacement-then-clean
  c-replacement-then-trunc c-clean-then-human c-clean-then-replacement-then-human
)

# classify one case through <script>; stdout = the single verdict line
verdict_of() {  # <script> <case>
  local s="$1" c="$2" j v rc=0
  j=$(build_env "$c") || { printf 'HARNESS-BUILD-FAILED'; return 0; }
  v=$(printf '%s' "$j" | bash "$s" --classify 2>/dev/null) || rc=$?
  [[ "$rc" -eq 0 ]] || { printf 'HARNESS-RC-%s' "$rc"; return 0; }
  printf '%s' "$v"
}

# --- the classifier table ---------------------------------------------------------------------
echo "# classifier table"
for c in "${CASE_ORDER[@]}"; do
  CASES=$((CASES + 1)) # H4-anchor
  got=$(verdict_of "$SCRIPT" "$c")
  if [[ "$got" == "${EXPECT[$c]}" ]]; then ok "$c -> $got"; else bad "$c -> '$got' (expected '${EXPECT[$c]}')"; fi
done

# The discoverability probe from the plan: empty stdin prints skip:empty-body and exits 0.
CASES=$((CASES + 1))
probe_rc=0; probe_out=$(printf '' | bash "$SCRIPT" --classify 2>/dev/null) || probe_rc=$?
if [[ "$probe_rc" -eq 0 && "$probe_out" == "skip:empty-body" ]]; then ok "discoverability probe prints skip:empty-body, rc 0"; else bad "probe rc=$probe_rc out='$probe_out'"; fi

# --- stub gh + end-to-end loop ----------------------------------------------------------------
# The stub dispatches on argv, records every call and REFUSES an unexpected one (rc 64), so a
# close issued on a wrong path, or a wrong read shape, is observable. A failing view can emit
# partial stdout: gh does that, and it is the case where ignoring the rc is dangerous.
mk_gh() {  # <dir>
  assert_fixture_dir "$1"
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'EOF'
#!/usr/bin/env bash
d="${MOCK_DIR:?}"
printf 'CALL:%s\n' "$*" >> "$d/calls.log"
case "${1:-} ${2:-}" in
  "issue list")
    if [[ -f "$d/list.rc" ]]; then exit "$(cat "$d/list.rc")"; fi
    cat "$d/list.out"; exit 0 ;;
  "issue view")
    n="${3:-}"
    [[ " $* " == *" --json body,comments "* ]] || { echo "UNEXPECTED view args: $*" >&2; exit 64; }
    [[ -f "$d/view.$n.out" ]] && cat "$d/view.$n.out"
    rc=0; [[ -f "$d/view.$n.rc" ]] && rc=$(cat "$d/view.$n.rc")
    exit "$rc" ;;
  "issue close")
    n="${3:-}"
    printf 'CLOSE:%s:%s\n' "$n" "$*" >> "$d/closes.log" # H3-anchor
    rc=0; [[ -f "$d/close.rc" ]] && rc=$(cat "$d/close.rc")
    exit "$rc" ;;
esac
echo "UNEXPECTED gh $*" >&2
exit 64
EOF
  chmod +x "$1/bin/gh"
}
view_json() {  # <bodyfile> [commentfile...]  -> gh issue view --json body,comments shape
  local j c
  j=$(jq -n --rawfile b "$1" '{body:$b,comments:[]}') || return 1
  shift
  for c in "$@"; do j=$(jq --rawfile c "$c" '.comments += [{body:$c}]' <<<"$j") || return 1; done
  printf '%s' "$j"
}
# run_loop <script> <scenario-dir> ; sets LOOP_RC and LOOP_OUT
run_loop() {
  local s="$1" d="$2"
  LOOP_RC=0
  LOOP_OUT=$(PATH="$d/bin:$PATH" MOCK_DIR="$d" GH_TOKEN=x MERGE_SHA=abc1234 \
    GITHUB_STEP_SUMMARY="$d/summary.md" bash "$s" 2>&1) || LOOP_RC=$?
}
new_scenario() { local d; d=$(mk_sandbox) || return 1; assert_fixture_dir "$d"; mk_gh "$d"; : > "$d/calls.log"; : > "$d/closes.log"; printf '%s' "$d"; }

scn_two_issues() {  # 21 clean, 22 replacement
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '21\n22\n' > "$d/list.out"
  view_json "$FIX/clean.body.md" > "$d/view.21.out"
  view_json "$FIX/replacement-present.body.md" > "$d/view.22.out"
  printf '%s' "$d"
}
scn_view_partial() {  # view fails (rc 1) but printed a CLEAN document first
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '11\n' > "$d/list.out"
  view_json "$FIX/clean.body.md" > "$d/view.11.out"
  printf '1' > "$d/view.11.rc"
  printf '%s' "$d"
}
scn_view_garbage() {
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '12\n' > "$d/list.out"
  printf 'this is not json' > "$d/view.12.out"
  printf '%s' "$d"
}
scn_list_fails() {
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '1' > "$d/list.rc"
  printf '%s' "$d"
}
scn_empty_list() {
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  : > "$d/list.out"
  printf '%s' "$d"
}
scn_close_fails() {  # two clean issues, every close fails
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '41\n42\n' > "$d/list.out"
  view_json "$FIX/clean.body.md" > "$d/view.41.out"
  view_json "$FIX/clean.body.md" > "$d/view.42.out"
  printf '1' > "$d/close.rc"
  printf '%s' "$d"
}
scn_comment_replacement() {
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf '31\n' > "$d/list.out"
  view_json "$FIX/clean.body.md" "$FIX/comment-replacement.md" > "$d/view.31.out"
  printf '%s' "$d"
}
scn_nonnumeric() {  # a non-numeric list entry must never reach gh issue view/close
  local d; d=$(new_scenario)
  assert_fixture_dir "$d"
  printf 'abc\n51\n' > "$d/list.out"
  view_json "$FIX/clean.body.md" > "$d/view.51.out"
  printf '%s' "$d"
}

echo "# end-to-end loop (stub gh)"
d=$(scn_two_issues); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
n_close=$(grep -c '^CLOSE:' "$d/closes.log" || true)
if [[ "$LOOP_RC" -eq 0 && "$n_close" -eq 1 ]] && grep -q '^CLOSE:21:' "$d/closes.log" \
   && grep -q -- '--reason completed' "$d/closes.log" && grep -q -- '--comment' "$d/closes.log"; then
  ok "two issues: exactly one close, for the clean one, with --reason completed and a comment"
else bad "two-issue run: rc=$LOOP_RC closes=$n_close log=$(cat "$d/closes.log")"; fi
CASES=$((CASES + 1))
if grep -qF '::notice::drift-autoclose: #22 left OPEN (hcloud-server-replacement)' <<<"$LOOP_OUT"; then
  ok "the skipped issue is named in a ::notice:: with its reason"
else bad "no per-issue notice for #22: $LOOP_OUT"; fi
CASES=$((CASES + 1))
if grep -qF 'considered=2 closed=1 skipped=1 close_failed=0' <<<"$LOOP_OUT" \
   && grep -qF 'considered=2 closed=1 skipped=1 close_failed=0' "$d/summary.md"; then
  ok "counter line is printed and mirrored to the step summary"
else bad "counter line missing: $LOOP_OUT"; fi
CASES=$((CASES + 1))
if grep -qF 'CALL:issue view 21 --json body,comments' "$d/calls.log" && grep -qF 'CALL:issue view 22 --json body,comments' "$d/calls.log"; then
  ok "each issue is read once, body and comments in one call"
else bad "read shape wrong: $(cat "$d/calls.log")"; fi

d=$(scn_view_partial); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1)) # e2e-partial
if [[ "$LOOP_RC" -eq 0 && ! -s "$d/closes.log" ]] && grep -qF '#11 left OPEN (gh-view-failed)' <<<"$LOOP_OUT"; then
  ok "a failing gh view (even with clean partial stdout) never closes"
else bad "view failure closed or was not reported: rc=$LOOP_RC out=$LOOP_OUT closes=$(cat "$d/closes.log")"; fi

d=$(scn_view_garbage); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
if [[ "$LOOP_RC" -eq 0 && ! -s "$d/closes.log" ]] && grep -qF '#12 left OPEN (gh-view-failed)' <<<"$LOOP_OUT"; then
  ok "an unparseable gh view never closes"
else bad "garbage view closed or was not reported: rc=$LOOP_RC out=$LOOP_OUT"; fi

d=$(scn_list_fails); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
if [[ "$LOOP_RC" -eq 1 ]] && grep -qF '::error::' <<<"$LOOP_OUT" && [[ ! -s "$d/closes.log" ]]; then
  ok "an unreadable issue list is ::error:: and exit 1 (pre-change behaviour kept)"
else bad "list failure: rc=$LOOP_RC out=$LOOP_OUT"; fi

d=$(scn_empty_list); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
if [[ "$LOOP_RC" -eq 0 ]] && grep -qF 'considered=0 closed=0 skipped=0 close_failed=0' <<<"$LOOP_OUT"; then
  ok "an empty list says so (considered=0) and exits 0"
else bad "empty list: rc=$LOOP_RC out=$LOOP_OUT"; fi

d=$(scn_close_fails); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
n_close=$(grep -c '^CLOSE:' "$d/closes.log" || true)
if [[ "$LOOP_RC" -eq 0 && "$n_close" -eq 2 ]] && grep -qF '::warning::' <<<"$LOOP_OUT" \
   && grep -qF 'close_failed=2' <<<"$LOOP_OUT"; then
  ok "a failed close is a ::warning:: and the loop continues to the next issue"
else bad "close failure handling: rc=$LOOP_RC closes=$n_close out=$LOOP_OUT"; fi

d=$(scn_comment_replacement); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
if [[ ! -s "$d/closes.log" ]] && grep -qF '#31 left OPEN (hcloud-server-replacement)' <<<"$LOOP_OUT"; then
  ok "a replacement shown only in the newest comment keeps the issue open"
else bad "comment replacement closed: $LOOP_OUT"; fi

d=$(scn_nonnumeric); run_loop "$SCRIPT" "$d"
CASES=$((CASES + 1))
if ! grep -qE 'issue (view|close) abc' "$d/calls.log" && grep -q '^CLOSE:51:' "$d/closes.log"; then
  ok "a non-numeric list entry never reaches gh view/close; the valid one still closes"
else bad "non-numeric handling: calls=$(cat "$d/calls.log")"; fi

# --- workflow wiring --------------------------------------------------------------------------
# The step is located BY NAME with a real YAML parse (not a grep), and must be one script call.
wiring_check() {  # <workflow-yaml> -> prints "ok" or a reason
  python3 - "$1" "$REPO" "$STEP_NAME" <<'PY'
import os, re, sys
try:
    import yaml
except Exception as e:  # pragma: no cover
    print("no-yaml-module"); sys.exit(0)
wf, repo, name = sys.argv[1:4]
doc = yaml.safe_load(open(wf))
steps = []
for job in (doc.get("jobs") or {}).values():
    for st in job.get("steps") or []:
        steps.append(st)
named = [s for s in steps if s.get("name") == name]
if len(named) != 1:
    print("step-found:%d" % len(named)); sys.exit(0)
st = named[0]
run = st.get("run") or ""
m = re.search(r'scripts/infra-drift-autoclose\.sh', run)
if not m:
    print("step-does-not-call-the-script"); sys.exit(0)
if "gh issue close" in run:
    print("inline-gh-issue-close"); sys.exit(0)
mm = re.search(r'\$\{GITHUB_WORKSPACE\}/([^"\s]+)', run)
rel = mm.group(1) if mm else ""
if rel != "scripts/infra-drift-autoclose.sh":
    print("invoked-path-is-not-the-script:" + rel); sys.exit(0)
p = os.path.join(repo, rel)
if not (os.path.isfile(p) and os.access(p, os.X_OK)):
    print("script-not-executable-or-missing:" + rel); sys.exit(0)
env = st.get("env") or {}
for k in ("GH_TOKEN", "MERGE_SHA"):
    if k not in env:
        print("env-missing:" + k); sys.exit(0)
# no OTHER step may close infra-drift issues
for s in steps:
    if s is st: continue
    r = s.get("run") or ""
    if "gh issue close" in r and "infra-drift" in r:
        print("second-closer:" + str(s.get("name"))); sys.exit(0)
print("ok")
PY
}
echo "# workflow wiring"
CASES=$((CASES + 1))
w=$(wiring_check "$WORKFLOW")
if [[ "$w" == "ok" ]]; then ok "the step is one invocation of the script, no inline gh issue close, env intact"; else bad "wiring: $w"; fi

# ---------------------------------------------------------------------------------------------
# Harness self-tests (always on): bad() must record a FAILURE into FAIL and the append-only
# ledger; ok() must move PASS. An assertion harness never shown to emit a FAIL has not returned
# a pass. Runs in a subshell so the side effects stay off the parent's tally.
# ---------------------------------------------------------------------------------------------
if ( _p0="$PASS"; _f0="$FAIL"; _l0="${#FAILURES[@]}"
     bad "self-test (expected -- this line proves bad() records a FAILURE)" >/dev/null 2>&1
     [[ "$FAIL" -eq $((_f0 + 1)) && "$PASS" -eq "$_p0" && "${#FAILURES[@]}" -eq $((_l0 + 1)) ]] ); then
  :
else
  echo "harness self-test: the REAL bad() does not record a failure -- it is neutered, or records failures as passes. Every verdict above is unverifiable." >&2
  exit 1
fi
if ( _p0="$PASS"; _f0="$FAIL"
     ok "self-test (expected -- this line proves ok() records a PASS)" >/dev/null 2>&1
     [[ "$PASS" -eq $((_p0 + 1)) && "$FAIL" -eq "$_f0" ]] ); then
  :
else
  echo "harness self-test: the REAL ok() does not record a pass." >&2
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# Mutation battery + harness rows. Skipped when re-invoked by a harness row (no recursion).
# ---------------------------------------------------------------------------------------------
fatal_harness() { printf '\n[FATAL] %s\n' "$1" >&2; exit 2; }

mutate_func() {  # <out> <funcname> <replacement-one-liner> ; replaces the WHOLE function
  python3 - "$SCRIPT" "$1" "$2" "$3" <<'PY' || return 1
import re, sys
src, out, fn, new = sys.argv[1:5]
t = open(src).read()
pat = re.compile(r'(?ms)^' + re.escape(fn) + r'\(\) \{.*?^\}\n')
t2, n = pat.subn(lambda m: fn + '() { ' + new + '; }\n', t, count=1)
if n != 1:
    sys.exit(3)
open(out, 'w').write(t2)
PY
}
mutate_marker() {  # <out> <marker> <replacement-line> ; replaces the line carrying '# mut:<marker>'
  python3 - "${MSRC:-$SCRIPT}" "$1" "$2" "$3" <<'PY' || return 1
import sys
src, out, marker, new = sys.argv[1:5]
tag = '# mut' + ':' + marker
lines = open(src).read().split('\n')
hit = [i for i, l in enumerate(lines) if tag in l]
if len(hit) != 1:
    sys.exit(3)
indent = lines[hit[0]][:len(lines[hit[0]]) - len(lines[hit[0]].lstrip())]
lines[hit[0]] = indent + new
open(out, 'w').write('\n'.join(lines))
PY
}
landed() {  # <mutant> : the mutant must differ from the original AND still parse
  [[ -s "$1" ]] || fatal_harness "mutant $1 empty -- the mutation did not land (vacuous row)"
  if cmp -s "$SCRIPT" "$1"; then fatal_harness "mutant $1 is identical to the original -- the mutation did not land (vacuous row)"; fi
  bash -n "$1" || fatal_harness "mutant $1 does not parse -- a syntax error is neither a pass nor a fail"
}

if [[ -z "${DRIFT_NO_BATTERY:-}" ]]; then
  echo "# mutation battery (each mutant must change the verdict of its target cases)"
  MUT="$(mk_sandbox)"
  assert_fixture_dir "$MUT"

  # control: the unmutated script reproduces the table (a red control voids every row)
  for c in replacement-present truncated-cut clean; do
    [[ "$(verdict_of "$SCRIPT" "$c")" == "${EXPECT[$c]}" ]] || fatal_harness "unmutated control is not green on $c"
  done

  row_cases() {  # <label> <mutant> <case>... : every target case must differ from EXPECT
    local label="$1" m="$2" c got bad_list=""
    shift 2
    landed "$m"
    CASES=$((CASES + 1))
    for c in "$@"; do
      got=$(verdict_of "$m" "$c")
      [[ "$got" != "${EXPECT[$c]}" ]] || bad_list="$bad_list $c"
    done
    if [[ -z "$bad_list" ]]; then ok "mutation $label flips: $*"; else bad "mutation $label NOT caught for:$bad_list"; fi
  }

  mutate_func "$MUT/m1.sh" has_hcloud_replacement 'return 1' || fatal_harness "m1 did not apply"
  row_cases "1 neuter has_hcloud_replacement" "$MUT/m1.sh" replacement-present replacement-crlf r1-indexed r1-destroyed
  mutate_func "$MUT/m2.sh" normalize 'printf "%s" "$1"' || fatal_harness "m2 did not apply"
  row_cases "2 neuter normalize" "$MUT/m2.sh" replacement-escaped-only replacement-double-escaped truncated-title-escaped
  mutate_func "$MUT/m3.sh" has_complete_terminator 'return 0' || fatal_harness "m3 did not apply"
  row_cases "3 neuter has_complete_terminator" "$MUT/m3.sh" truncated-cut no-terminator
  mutate_func "$MUT/m4.sh" has_truncation_marker 'return 1' || fatal_harness "m4 did not apply"
  row_cases "4 neuter has_truncation_marker" "$MUT/m4.sh" truncated-title truncated-title-escaped
  # both guards removed at once: either alone is covered by the other (defence in depth)
  mutate_marker "$MUT/m6a.sh" empty ':' || fatal_harness "m6a did not apply"
  MSRC="$MUT/m6a.sh" mutate_marker "$MUT/m6.sh" noplan ':' || fatal_harness "m6b did not apply"
  row_cases "6 remove the empty-body and no-plan guards" "$MUT/m6.sh" empty-body whitespace-body no-plan-block empty-stdin
  mutate_marker "$MUT/m8.sh" last-artifact 'sel=$first_plan_idx' || fatal_harness "m8 did not apply"
  row_cases "8 judge the FIRST plan-bearing artifact, not the newest" "$MUT/m8.sh" c-clean-then-replacement c-clean-then-truncated
  mutate_marker "$MUT/m10.sh" terminator 'if [[ "$sel" -eq 0 ]] && ! has_complete_terminator "$art" "$norm"; then verdict=skip:plan-incomplete; fi' \
    || fatal_harness "m10 did not apply"
  row_cases "10 run the terminator check on the body only" "$MUT/m10.sh" c-clean-then-truncated c-replacement-then-trunc
  mutate_marker "$MUT/m11.sh" r1-actions "R1_ACTIONS='must be replaced'" || fatal_harness "m11 did not apply"
  row_cases "11 narrow R1's action alternation to 'must be replaced'" "$MUT/m11.sh" r1-destroyed r1-created r1-as-requested
  mutate_marker "$MUT/m12.sh" r2 "R2='NEVER-MATCHES-ANYTHING-XYZ'" || fatal_harness "m12 did not apply"
  row_cases "12 neuter the -/+ resource marker (R2)" "$MUT/m12.sh" r2-only

  # --- loop mutants: scored through the stub-gh end-to-end ---------------------------------
  row_loop() {  # <label> <mutant> <scenario-fn> ; the scenario must record a WRONG close under the mutant
    local label="$1" m="$2" scn="$3" d n_close wrong=0
    landed "$m"
    CASES=$((CASES + 1))
    d=$("$scn"); run_loop "$m" "$d"
    n_close=$(grep -c '^CLOSE:' "$d/closes.log" || true)
    case "$scn" in
      scn_two_issues)   if [[ "$n_close" -ne 1 ]] || ! grep -q '^CLOSE:21:' "$d/closes.log"; then wrong=1; fi ;;
      scn_view_partial) if [[ "$n_close" -ge 1 ]]; then wrong=1; fi ;;
    esac
    if [[ "$wrong" -eq 1 ]]; then ok "mutation $label records a wrong close (closes=$n_close)"; else bad "mutation $label NOT caught (closes=$n_close)"; fi
  }
  # read_issue's own guard: with it gone, a failing gh's partial stdout is passed on as a clean read
  mutate_marker "$MUT/m5.sh" readguard ':' || fatal_harness "m5 did not apply"
  row_loop "5 swallow a failed gh view's rc" "$MUT/m5.sh" scn_view_partial
  mutate_marker "$MUT/m7.sh" verdict 'verdict=close' || fatal_harness "m7 did not apply"
  row_loop "7 dispatch: constant close instead of classify" "$MUT/m7.sh" scn_two_issues
  mutate_marker "$MUT/m9.sh" verdict 'verdict=${CACHED_V:-$(classify <<<"$envj")}; CACHED_V=$verdict' || fatal_harness "m9 did not apply"
  row_loop "9 reuse the FIRST issue's verdict for every issue" "$MUT/m9.sh" scn_two_issues

  # --- workflow-wiring mutants W1-W3 -------------------------------------------------------
  wmut() {  # <out> <python-edit-expr on t>
    python3 - "$WORKFLOW" "$1" "$2" "$STEP_NAME" <<'PY' || return 1
import sys
src, out, mode, name = sys.argv[1:5]
t = open(src).read()
if mode == "W1":
    key = 'bash "${GITHUB_WORKSPACE}/scripts/infra-drift-autoclose.sh"'
    if t.count(key) != 1: sys.exit(3)
    t = t.replace(key, key + '\n          gh issue close "$n" --reason completed')
elif mode == "W2":
    key = 'bash "${GITHUB_WORKSPACE}/scripts/infra-drift-autoclose.sh"'
    if t.count(key) != 1: sys.exit(3)
    t = t.replace(key, 'bash "${GITHUB_WORKSPACE}/scripts/infra-drift-autoclose.sh.missing"')
elif mode == "W3":
    key = 'name: ' + name
    if t.count(key) != 1: sys.exit(3)
    t = t.replace(key, 'name: Renamed away')
open(out, 'w').write(t)
PY
  }
  for m in W1 W2 W3; do
    wmut "$MUT/$m.yml" "$m" || fatal_harness "wiring mutation $m did not apply"
    if cmp -s "$WORKFLOW" "$MUT/$m.yml"; then fatal_harness "wiring mutation $m did not change the workflow"; fi
    CASES=$((CASES + 1))
    w=$(wiring_check "$MUT/$m.yml")
    if [[ "$w" != "ok" ]]; then ok "wiring mutation $m caught ($w)"; else bad "wiring mutation $m NOT caught"; fi
  done

  # --- harness rows H1-H4: edits to the SUITE, re-invoked with the battery off --------------
  child() { DRIFT_NO_BATTERY=1 DRIFT_TEST_HERE="$HERE" DRIFT_FIXTURE_DIR="${2:-$FIX}" bash "$1" >/dev/null 2>&1; }
  assert_fixture_dir "$MUT"
  cp "${BASH_SOURCE[0]}" "$MUT/suite.ok.sh"
  CASES=$((CASES + 1))
  if child "$MUT/suite.ok.sh"; then ok "harness control: the suite re-invoked unmutated with the battery off is green"; else fatal_harness "unmutated child suite is not green -- every harness row would be void"; fi
  hmut() {  # <out> <mode>
    python3 - "${BASH_SOURCE[0]}" "$1" "$2" <<'PY' || return 1
import sys
src, out, mode = sys.argv[1:4]
lines = open(src).read().split('\n')
def find(tag):
    h = [i for i, l in enumerate(lines) if tag in l and 'python3' not in l and 'tag' not in l]
    return h
if mode == 'H1':
    h = [i for i, l in enumerate(lines) if l.startswith('bad() {')]
    if len(h) != 1: sys.exit(3)
    lines[h[0]] = 'bad() { echo "  PASS: $1"; PASS=$((PASS + 1)); }'
elif mode == 'H3':
    tag = 'H3' + '-anchor'
    h = [i for i, l in enumerate(lines) if l.rstrip().endswith('# ' + tag)]
    if len(h) != 1: sys.exit(3)
    lines[h[0]] = '    : # dropped'
elif mode == 'H4':
    tag = 'H4' + '-anchor'
    h = [i for i, l in enumerate(lines) if l.rstrip().endswith('# ' + tag)]
    if len(h) != 1: sys.exit(3)
    lines[h[0]] = '  : # dropped'
open(out, 'w').write('\n'.join(lines))
PY
  }
  for m in H1 H3 H4; do
    hmut "$MUT/suite.$m.sh" "$m" || fatal_harness "harness mutation $m did not apply"
    cmp -s "${BASH_SOURCE[0]}" "$MUT/suite.$m.sh" && fatal_harness "harness mutation $m did not change the suite"
    CASES=$((CASES + 1))
    if child "$MUT/suite.$m.sh"; then bad "harness row $m NOT caught (the mutated suite still exits 0)"; else ok "harness row $m caught (the mutated suite exits non-zero)"; fi
  done
  # H2: an emptied fixture must red the suite
  assert_fixture_dir "$MUT"
  mkdir -p "$MUT/fix-h2" && cp "$FIX"/* "$MUT/fix-h2/" && : > "$MUT/fix-h2/clean.body.md"
  CASES=$((CASES + 1))
  if child "$MUT/suite.ok.sh" "$MUT/fix-h2"; then bad "harness row H2 NOT caught (an emptied fixture still exits 0)"; else ok "harness row H2 caught (an emptied fixture reds the suite)"; fi
fi

# ---------------------------------------------------------------------------------------------
# Accounting identity: PASS + FAIL == CASES. Reported directly (not through bad()) so neutering
# the helpers cannot hide it. A counted case with no verdict is what a neutered ok()/bad() or a
# dropped call-site increment looks like.
# ---------------------------------------------------------------------------------------------
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: %d verdict(s) recorded across %d counted case(s).\n' "$((PASS + FAIL))" "$CASES" >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi

if [[ -z "${DRIFT_NO_BATTERY:-}" ]]; then
DRIFT_MIN_ASSERTIONS=78
if [[ "$CASES" -lt "$DRIFT_MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$DRIFT_MIN_ASSERTIONS" >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
[[ "$FAIL" -eq 0 && "${#FAILURES[@]}" -eq 0 ]] || exit 1
