#!/usr/bin/env bash
# Suite for scripts/watch-brand-hex-triggers-11177.sh (the weekly watcher that tests the two
# "re-evaluate when" triggers on the brand-hex-gate tracker #11177 and comments ONLY when one
# fires). Mock-`gh` + fixture-git-repo pattern: a PATH-prepended recording `gh` (real flags only,
# real stderr shapes, exit 64 on anything unexpected) serves per-scenario issue JSON and logs every
# argv; each fixture repo carries a COPY OF THE REAL gate and its libs, so a gate rewrite that
# breaks the invocation contract reds this suite (Guard 4 anchor). Fixtures are synthesized only;
# the offending colour is an off-palette raw hex.
#
# Mutation rows run against a MUTATED COPY of the script and lib in a scratch dir, with a
# pristine-copy cmp proving each mutation landed and an unmutated control required GREEN first.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-brand-hex-triggers-11177.sh"
LIBF="$SCRIPT_DIR/lib/watch-notify-once.sh"
REAL_HOOKS="$SCRIPT_DIR/../.claude/hooks"
WF="$SCRIPT_DIR/../.github/workflows/code-quality-followups-watch.yml"

PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
# The verdict. The LAST line of this file must be exactly `finish || exit 1`; the self-test
# below drives it both ways and pins that line, so neither the function nor its wiring can be
# neutered while a real failure is present.
finish() { [[ "$FAIL" -eq 0 ]]; }

# Instrument self-test (ADR-193): drive both branches, require both counters to move, report
# with printf + exit, never through the helpers under test.
pass "self-test" >/dev/null
fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 2
fi
PASS=0; FAIL=0; TOTAL=0
if ( FAIL=1; finish ) || ! ( FAIL=0; finish ); then
  printf 'FATAL: finish() does not map FAIL to an exit status\n' >&2
  exit 2
fi
if [[ "$(tail -n 1 "${BASH_SOURCE[0]}")" != 'finish || exit 1' ]]; then
  printf 'FATAL: the last line of this suite is not the exit gate `finish || exit 1`\n' >&2
  exit 2
fi

# A fixture repo must never see the caller's git location variables.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Fixture-directory guard. The CANONICAL copy lives in plugins/soleur/test/test-helpers.sh;
# plugins/soleur/test/fixture-dir-operand-assert.test.sh asserts this copy is byte-equal to it.
# Do not reword it in one file only.
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

# ONE owning tempdir with ONE trap (ADR-129); every scenario takes a subdirectory.
TMPDIR="${TMPDIR:-/var/tmp}"; export TMPDIR
ROOT="$(mktemp -d "${TMPDIR%/}/watch-brand-hex.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

# The exit-gate check re-runs this whole suite with one injected failure. It is started HERE, in
# the background, and collected at the end, so its wall time overlaps the main run instead of
# doubling it (the two runs own separate tempdirs).
nested_pid=""
if [[ -z "${WBH_INJECT_FAIL:-}" ]]; then
  WBH_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 &
  nested_pid=$!
fi

ISSUE=11177
CREATED='2026-10-26T11:33:12Z'
WIN_T0="$(date -u -d 2026-10-27T00:00:00Z +%s)"   # fixture commits inside the window start here
OLD_T0="$(date -u -d 2026-10-20T00:00:00Z +%s)"   # fixture commits older than the tracker
BASE_T0="$(date -u -d 2026-10-01T00:00:00Z +%s)"
OFF_TSX='export const s = { color: "#ff00aa" };'
TOK_TSX='export const s = { color: "var(--soleur-gold)" };'
PAL_HEX='#c9a962'
OFF_HEX='#ff00aa'
VIEW_ARGV="issue view $ISSUE --json state,createdAt,comments"
POST_ARGV="issue comment $ISSUE --body-file -"
SENT_RE='^<!-- code-quality-followups-watch:[a-z0-9:-]+ -->$'
# A synthesized, token-SHAPED dummy built by concatenation (never a real credential).
DUMMY_TOKEN="ghs_""$(printf 'q%.0s' 1 2 3 4 5 6 7 8)"

N=0; K=0; TICK=0
REPO=""; MOCKD=""; OUT=""; ERR=""; RC=0; LAST=""; DIAG=""
RUN_ENV=(); RUN_PATH=""; SUT_UNDER="$SUT"; MOCK_DEAD=0; CLK=""

# ------------------------------------------------------------------ fixtures ----
REAL_COPY="$ROOT/real-hooks"; TPL="$ROOT/tpl"; WRAPPER_SRC="$ROOT/gate-wrapper.sh"; MOCK_SRC="$ROOT/mock-gh.sh"
assert_fixture_dir "$REAL_COPY"; assert_fixture_dir "$TPL"
mkdir -p "$REAL_COPY/lib" "$TPL/.claude/hooks/lib" "$TPL/apps/web-platform/app" "$TPL/apps/web-platform/components" "$TPL/apps/web-platform/server" "$TPL/plugins/soleur/hooks" "$TPL/docs" \
  || fatal "template mkdir failed"
for f in brand-hex-commit-gate.sh git-commit-secret-scan.sh; do
  [[ -f "$REAL_HOOKS/$f" ]] || fatal "real hook missing: $f"
  cp "$REAL_HOOKS/$f" "$TPL/.claude/hooks/$f" && cp "$REAL_HOOKS/$f" "$REAL_COPY/$f" || fatal "copy failed: $f"
done
for f in "$REAL_HOOKS"/lib/*.sh; do
  case "$f" in *.test.sh) continue ;; esac
  cp "$f" "$TPL/.claude/hooks/lib/${f##*/}" && cp "$f" "$REAL_COPY/lib/${f##*/}" || fatal "copy failed: $f"
done
printf ':root { --soleur-bg: #0a0a0a; --soleur-gold: %s; }\n' "$PAL_HEX" > "$TPL/apps/web-platform/app/globals.css"
printf '%s\n' "$TOK_TSX" > "$TPL/apps/web-platform/app/page.tsx"
printf 'const h = "<td style=\\"color: %s\\">";\n' "$PAL_HEX" > "$TPL/apps/web-platform/server/invite-email.ts"
printf '#!/usr/bin/env bash\necho session\n' > "$TPL/plugins/soleur/hooks/session.sh"
printf 'notes\n' > "$TPL/docs/readme.md"
git init -q -b main "$TPL" || fatal "template git init failed"
git -C "$TPL" add -A || fatal "template add failed"
GIT_AUTHOR_DATE="@$BASE_T0 +0000" GIT_COMMITTER_DATE="@$BASE_T0 +0000" \
  git -C "$TPL" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m base || fatal "template commit failed"

# The recording gh. Real flags only, real stderr shapes, exit 64 on anything else.
cat > "$MOCK_SRC" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCKD/calls"
case "$1 $2" in
  "issue view")
    [[ "$*" == "issue view 11177 --json state,createdAt,comments" ]] || { echo "mock gh: unexpected view argv: $*" >&2; exit 64; }
    if [[ -f "$MOCKD/view_gone" ]]; then echo 'GraphQL: Could not resolve to an issue or pull request with the number of 11177. (repository.issue)' >&2; exit 1; fi
    if [[ -f "$MOCKD/view_fail" ]]; then echo 'error connecting to api.github.com' >&2; exit 1; fi
    cat "$MOCKD/issue.json"; exit 0 ;;
  "issue comment")
    [[ "$*" == "issue comment 11177 --body-file -" ]] || { echo "mock gh: unexpected comment argv: $*" >&2; exit 64; }
    if [[ -f "$MOCKD/comment_fail" ]]; then cat >/dev/null; echo 'gh: Bad Gateway (HTTP 502)' >&2; exit 1; fi
    c=0; for b in "$MOCKD"/body.*; do [[ -e "$b" ]] && c=$((c + 1)); done
    cat > "$MOCKD/body.$((c + 1))"; exit 0 ;;
esac
echo "mock gh: unexpected invocation: $*" >&2; exit 64
MOCK

# The gate wrapper installed ON DISK only (the committed history keeps the real gate). It logs
# every run, forces a verdict on demand, and otherwise delegates to the real gate copy.
cat > "$WRAPPER_SRC" <<'WRAP'
#!/usr/bin/env bash
payload="$(cat)"
[ -n "${FIX_GATE_LOG:-}" ] && printf 'run\n' >> "$FIX_GATE_LOG"
allow_json='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
case "${FIX_FORCE:-}" in
  allow) printf '%s\n' "$allow_json"; exit 0 ;;
  garbage) echo "this is not json"; exit 0 ;;
  warn) echo "[brand-hex-commit-gate] WARN: stub warning" >&2; printf '%s\n' "$allow_json"; exit 0 ;;
  deny) jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"BLOCKED: stub found 1 raw hex colour literal(s) in staged UI/template content. Locations: apps/web-platform/app/stub.tsx:1 (component #ff00aa; use a design token). Remediation: stub"}}'; exit 0 ;;
  slow) sleep 2 ;;
esac
names="$(git diff --cached --name-only 2>/dev/null)"
case "$names" in
  *zz-timeout*) exit 124 ;;
  *zz-warn*) echo "[brand-hex-commit-gate] WARN: stub warning" >&2; printf '%s\n' "$allow_json"; exit 0 ;;
  *zz-garbage*) echo "{not json"; exit 0 ;;
  *zz-slow*) exec sleep 30 ;;
esac
printf '%s' "$payload" | exec bash "$FIX_REAL/brand-hex-commit-gate.sh"
WRAP
# The watcher reads the path classes from the gate file that will run; the wrapper carries the real
# gate's two class lines (never executed here, after the exec) so that contract stays honest.
grep -E '^(UI_RE|EMAIL_RE)=' "$REAL_HOOKS/brand-hex-commit-gate.sh" >> "$WRAPPER_SRC" || fatal "gate class lines not found"

g() { assert_fixture_dir "$REPO"; git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

mkrepo() {
  N=$((N + 1)); TICK=0
  REPO="$ROOT/repo$N"; MOCKD="$ROOT/mock$N"
  assert_fixture_dir "$REPO"; assert_fixture_dir "$MOCKD"
  cp -a "$TPL" "$REPO" || fatal "cp template failed"
  mkdir -p "$MOCKD/tmp" || fatal "mkdir mock failed"
  : > "$MOCKD/calls"; : > "$MOCKD/gatelog"
  cp "$MOCK_SRC" "$MOCKD/gh" || fatal "cp mock failed"
  if [[ "$MOCK_DEAD" -eq 1 ]]; then grep -v '^printf .%s.n. "\$\*" >> "\$MOCKD/calls"$' "$MOCK_SRC" > "$MOCKD/gh" || true; fi
  chmod +x "$MOCKD/gh"
  RUN_ENV=(); RUN_PATH=""
  issue OPEN "$CREATED" '[]'
}
issue() { assert_fixture_dir "$MOCKD"; jq -nc --arg s "$1" --arg c "$2" --argjson m "$3" '{state:$s,createdAt:$c,comments:$m}' > "$MOCKD/issue.json"; }
rawissue() { assert_fixture_dir "$MOCKD"; printf '%s' "$1" > "$MOCKD/issue.json"; }
cmt() { jq -nc --arg a "$1" --arg b "$2" '{author:{login:$a},body:$b}'; }
cl() { jq -sc .; }
sent() { printf '<!-- code-quality-followups-watch:%s -->' "$1"; }
flag() { assert_fixture_dir "$MOCKD"; : > "$MOCKD/$1"; }
use_wrapper() { assert_fixture_dir "$REPO"; cp "$WRAPPER_SRC" "$REPO/.claude/hooks/brand-hex-commit-gate.sh" || fatal "wrapper install failed"; }

clock() { TICK=$((TICK + 1)); CLK="@$(( ${CLOCK_BASE:-$WIN_T0} + TICK * 60 )) +0000"; }
gcommit() { clock; GIT_AUTHOR_DATE="$CLK" GIT_COMMITTER_DATE="$CLK" g commit -q -m "$1" || fatal "fixture commit failed: $1"; }
put() { assert_fixture_dir "$REPO"; mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "$2" > "$REPO/$1"; }
# fc PATH CONTENT SUBJECT: write, stage only that path, commit inside the window. LAST = new sha.
fc() { put "$1" "$2"; g add -- "$1" || fatal "add failed: $1"; gcommit "$3"; LAST="$(g rev-parse HEAD)"; }
fc_old() { CLOCK_BASE="$OLD_T0" fc "$@"; CLOCK_BASE=""; }
CLOCK_BASE=""
offend() { K=$((K + 1)); fc "apps/web-platform/app/o$K.tsx" "$OFF_TSX" "${1:-offending $K}"; }
clean() { K=$((K + 1)); fc "apps/web-platform/app/c$K.tsx" "$TOK_TSX" "${1:-clean $K}"; }
HOOK_SRC=$'#!/usr/bin/env bash\ncis_lib="$(dirname "${BASH_SOURCE[0]}")/lib/commit-index-sim.sh"\n. "$cis_lib"'

run() {
  OUT=""; ERR=""; RC=0
  assert_fixture_dir "$MOCKD"; assert_fixture_dir "$REPO"
  local o="$MOCKD/stdout" e="$MOCKD/stderr" p="${RUN_PATH:-$MOCKD:$PATH}"
  ( cd "$REPO" && env "PATH=$p" "MOCKD=$MOCKD" "TMPDIR=$MOCKD/tmp" "GH_TOKEN=$DUMMY_TOKEN" "FIX_REAL=$REAL_COPY" "FIX_GATE_LOG=$MOCKD/gatelog" \
      ${RUN_ENV[@]+"${RUN_ENV[@]}"} bash "$SUT_UNDER" "$@" ) > "$o" 2> "$e"
  RC=$?
  OUT="$(cat "$o")"; ERR="$(cat "$e")"
}
posted() { grep -c '^issue comment ' "$MOCKD/calls" || true; }
gate_runs() { grep -c '^run$' "$MOCKD/gatelog" || true; }
body_of() { printf '%s' "$MOCKD/body.$1"; }
calls_are() { [[ "$(cat "$MOCKD/calls")" == "$1" ]]; }
nsent() { grep -c "^<!-- code-quality-followups-watch:$2" "$1" || true; }
has_sent() { grep -qxF "$(sent "$2")" "$1"; }
worktrees_clean() { [[ "$(git -C "$REPO" worktree list | wc -l)" -eq 1 && -z "$(ls -A "$MOCKD/tmp")" ]]; }
need() { if ! eval "$1"; then DIAG="needed: $1 (rc=$RC err=${ERR:0:300} out=${OUT:0:300})"; return 1; fi; return 0; }

# The posted comment's hygiene: the sentinels are the exact tail block and the last line, no
# third-party text can contribute an HTML comment closer or opener, no @, no angle bracket,
# no closing keyword followed by a reference.
body_hygiene() {
  local f="$1" total tail_n nonsent
  [[ -s "$f" ]] || { DIAG="no body file $f"; return 1; }
  [[ "$(tail -n 1 "$f")" =~ $SENT_RE ]] || { DIAG="last line is not a sentinel"; return 1; }
  total="$(grep -cE "$SENT_RE" "$f" || true)"
  tail_n="$(awk -v re="$SENT_RE" '{a[NR]=$0} END{n=0; for(i=NR;i>=1;i--){ if (a[i] ~ re) n++; else break } print n}' "$f")"
  [[ "$total" -ge 1 && "$total" -eq "$tail_n" ]] || { DIAG="sentinels not a contiguous tail ($total vs $tail_n)"; return 1; }
  [[ "$(grep -o -- '-->' "$f" | wc -l)" -eq "$total" && "$(grep -o -- '<!--' "$f" | wc -l)" -eq "$total" ]] || { DIAG="stray HTML comment marker"; return 1; }
  nonsent="$(grep -vE "$SENT_RE" "$f")"
  if grep -q '@' <<<"$nonsent"; then DIAG="body carries an @"; return 1; fi
  if grep -q '[<>]' <<<"$nonsent"; then DIAG="body carries an angle bracket"; return 1; fi
  if grep -iEq '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[^#]{0,40}#[0-9]' <<<"$nonsent"; then DIAG="body carries a closing keyword + reference"; return 1; fi
  return 0
}

# One scenario = one check function returning 0 (expectations held) or 1 (DIAG explains).
scenario() { local label="$1" fn="$2"; DIAG=""; if "$fn"; then pass "$label"; else fail "$label [$DIAG]"; fi; }

# ===================================================================== checks =====
# ---- Guard 3: trigger 1 ----
chk_g3_clean() { # no extra hook: silent, trigger 2 reports examined=0 (nothing in the window)
  mkrepo; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"trigger1 hooks="*"fired=0"* && "$OUT" == *"examined=0"* ]]'
}
chk_g3_r1() { # a new hook sourcing the lib: one comment, trigger-1 sentinel last, exact call set
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "add hook"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(cat "$(body_of 1)")" == *"new-hook.sh"* ]]' || return 1
  need 'calls_are "$VIEW_ARGV"$'"'"'\n'"'"'"$POST_ARGV"' || return 1
  need 'has_sent "$(body_of 1)" "trigger-1:v1" && [[ "$(tail -n 1 "$(body_of 1)")" == "$(sent trigger-1:v1)" ]]' || return 1
  body_hygiene "$(body_of 1)"
}
chk_g3_r2() { # the lib named only in a whole-line comment: precision
  mkrepo; fc .claude/hooks/new-hook.sh $'#!/usr/bin/env bash\n# TODO: source lib/commit-index-sim.sh later\n   # commit-index-sim again\necho hi' "comment-only hook"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]]'
}
chk_g3_r3() { # the gate itself adopting the lib (the fix landing) must stay silent
  mkrepo; put .claude/hooks/brand-hex-commit-gate.sh "$(cat "$REPO/.claude/hooks/brand-hex-commit-gate.sh")"$'\n''. "$(dirname "$0")/lib/commit-index-sim.sh"'
  g add -- .claude/hooks/brand-hex-commit-gate.sh; gcommit "gate adopts the lib"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]]'
}
chk_g3_r4() { # a second extra hook after a compliant first: both listed; a plugin lib/ one is not
  mkrepo; fc .claude/hooks/first.sh "$HOOK_SRC" "first"; fc plugins/x/hooks/second.sh "$HOOK_SRC" "second"
  fc plugins/x/hooks/lib/third.sh "$HOOK_SRC" "third (lib)"; run
  local b; b="$(cat "$(body_of 1)" 2>/dev/null)"
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$b" == *"first.sh"* && "$b" == *"second.sh"* && "$b" != *"third.sh"* ]]'
}
chk_g3_r5() { # zero tracked hooks (files still on disk): cannot establish, never "clean"
  mkrepo; g rm -r -q --cached .claude/hooks plugins || fatal "untrack failed"; gcommit "untrack hooks"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"tracked hook"* ]]'
}
chk_g3_silent() { # .test.sh, lib/ files, an untracked file and a plugin lib file stay silent
  mkrepo; fc .claude/hooks/foo.test.sh "$HOOK_SRC" "test names lib"; fc .claude/hooks/lib/helper.sh "$HOOK_SRC" "lib file"
  fc plugins/x/hooks/lib/h.sh "$HOOK_SRC" "plugin lib file"; put .claude/hooks/untracked.sh "$HOOK_SRC"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]]'
}
chk_g3_seen() { # trigger 1 already notified by the bot: nothing; the viewing is still exactly one read
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "add hook"
  issue OPEN "$CREATED" "$(cmt github-actions "x"$'\n'"$(sent trigger-1:v1)" | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]]' && need 'calls_are "$VIEW_ARGV"'
}
chk_g2_prefix() { # a bot v10 sentinel and a human v1 sentinel must not suppress trigger-1:v1
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "add hook"
  issue OPEN "$CREATED" "$({ cmt github-actions "$(sent trigger-1:v10)"; cmt someone "$(sent trigger-1:v1)"; } | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]]'
}

# ---- Guard 4: trigger 2 ----
chk_g4_r1() { # a raw hex colour in a UI file: a finding naming the commit, route caveat, clean teardown
  mkrepo; fc apps/web-platform/app/x.tsx "$OFF_TSX" "add colour"; local sha="$LAST"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$OUT" == *"examined=1"* ]]' || return 1
  local b; b="$(cat "$(body_of 1)")"
  need '[[ "$b" == *"${sha:0:12}"* && "$b" == *"x.tsx"* && "$b" == *"cannot be inferred"* && "$b" != *"could not be judged"* ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$sha" && [[ "$(tail -n 1 "$(body_of 1)")" == "$(sent "trigger-2:$sha")" ]]' || return 1
  need 'calls_are "$VIEW_ARGV"$'"'"'\n'"'"'"$POST_ARGV"' || return 1
  need 'worktrees_clean' || return 1
  body_hygiene "$(body_of 1)"
}
chk_g4_r2() { # token reference, token-definition CSS: no finding (precision), both judged
  mkrepo; clean "token reference"; fc apps/web-platform/app/brand.tokens.css ":root { --x: $OFF_HEX; }" "token definition css"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"examined=2"* ]]'
}
chk_g4_r3() { # everything older than the tracker: a vacuous clean must say examined=0
  mkrepo; fc_old apps/web-platform/app/old.tsx "$OFF_TSX" "old offender"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"examined=0"* ]]'
}
chk_g4_r4() { # two offenders around a compliant commit: both reported
  mkrepo; offend; local s1="$LAST"; clean; offend; local s3="$LAST"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(nsent "$(body_of 1)" trigger-2:)" -eq 2 ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$s1" && has_sent "$(body_of 1)" "trigger-2:$s3"'
}
chk_g4_r6() { # email class: palette hex allowed, off-palette flagged, exactly the off-palette commit
  mkrepo; fc apps/web-platform/server/promo-email.ts "const a = '<td style=\"color: $PAL_HEX\">';" "palette hex"
  fc apps/web-platform/server/alert-email.ts "const b = '<td style=\"color: $OFF_HEX\">';" "off-palette hex"; local sha="$LAST"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(nsent "$(body_of 1)" trigger-2:)" -eq 1 ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$sha" && [[ "$(cat "$(body_of 1)")" == *"email"* ]]'
}
chk_g4_r7() { # reused worktree: clean <- offender <- clean reports exactly the offender
  mkrepo; clean; offend; local sha="$LAST"; clean; use_wrapper; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(nsent "$(body_of 1)" trigger-2:)" -eq 1 ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$sha" && [[ "$(gate_runs)" -eq 3 ]]'
}
chk_g4_outside() { # commits outside the path classes are skipped without running the gate
  mkrepo; fc docs/readme.md "more notes" "docs only"; fc scripts/tool.sh "echo tool" "script only"; clean "one class commit"; use_wrapper; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"examined=1"* && "$(gate_runs)" -eq 1 ]]'
}
chk_g4_merge() { # first-parent only: the side commit is not listed, the merge is judged
  mkrepo; clean "mainline base"; g checkout -q -b side || fatal "branch failed"
  fc apps/web-platform/app/side.tsx "$OFF_TSX" "side offender"; local side="$LAST"
  g checkout -q main || fatal "checkout failed"; clean "mainline work"
  clock; GIT_AUTHOR_DATE="$CLK" GIT_COMMITTER_DATE="$CLK" g merge -q --no-ff side -m "merge side" || fatal "merge failed"
  local merge; merge="$(g rev-parse HEAD)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$merge" && ! has_sent "$(body_of 1)" "trigger-2:$side"'
}
chk_sent_skip() { # a sentineled finding is not re-run through the gate and not re-posted
  mkrepo; offend; local sha="$LAST"; use_wrapper
  issue OPEN "$CREATED" "$(cmt github-actions "found"$'\n'"$(sent "trigger-2:$sha")" | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$(gate_runs)" -eq 0 ]]'
}
chk_g2_r3() { # bot holds the NEWEST finding; an older new one must still be posted, only it
  mkrepo; offend; local older="$LAST"; offend; local newer="$LAST"; use_wrapper
  issue OPEN "$CREATED" "$(cmt github-actions "found"$'\n'"$(sent "trigger-2:$newer")" | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(gate_runs)" -eq 1 ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$older" && ! has_sent "$(body_of 1)" "trigger-2:$newer"'
}
chk_g2_human() { # a human-pasted full sentinel and bot short/39-char prefixes do not suppress
  mkrepo; offend; local sha="$LAST"
  issue OPEN "$CREATED" "$({ cmt someone "$(sent "trigger-2:$sha")"; cmt github-actions "$(sent "trigger-2:${sha:0:7}")"; cmt github-actions "$(sent "trigger-2:${sha:0:39}")"; } | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]]' && need 'has_sent "$(body_of 1)" "trigger-2:$sha"'
}
chk_g2_bot_spelling() { # the REST spelling github-actions[bot] suppresses as well
  mkrepo; offend; local sha="$LAST"
  issue OPEN "$CREATED" "$(cmt 'github-actions[bot]' "$(sent "trigger-2:$sha")" | cl)"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]]'
}
chk_g2_malformed() { # a comment list jq cannot evaluate is exit 3, never "no sentinel"
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "add hook"; rawissue "{\"state\":\"OPEN\",\"createdAt\":\"$CREATED\",\"comments\":[\"x\"]}"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]]'
}
chk_over10() { # 12 findings: the body summarises (10 listed) and every finding is still sentineled
  mkrepo; local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do clean "case $i"; done
  use_wrapper; RUN_ENV=(FIX_FORCE=deny); run
  local b; b="$(cat "$(body_of 1)" 2>/dev/null)"
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(nsent "$(body_of 1)" trigger-2:)" -eq 12 && "$(grep -c "^- " "$(body_of 1)")" -eq 10 && "$b" == *"12 "* ]]' || return 1
  body_hygiene "$(body_of 1)"
}
chk_postfail() { # a failed post: exit 1 (the sentinel only ever lands with the comment)
  mkrepo; offend; flag comment_fail; run
  need '[[ "$RC" -eq 1 && "$(posted)" -eq 1 && "$ERR" == *"::error::"* ]]'
}
chk_unj_one() { # one timed-out commit: reported unjudgeable once, loop continues, next week it is not re-run
  mkrepo; clean "a"; fc apps/web-platform/app/zz-timeout.tsx "$TOK_TSX" "times out"; local unj="$LAST"; offend; local off="$LAST"; clean "d"
  use_wrapper; run
  local b; b="$(cat "$(body_of 1)" 2>/dev/null)"
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(gate_runs)" -eq 4 && "$b" == *"could not be judged by the gate (timeout or unusable output)"* ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2:$off" && has_sent "$(body_of 1)" "trigger-2-unjudgeable:$unj" && [[ "$(nsent "$(body_of 1)" trigger-2)" -eq 2 ]]' || return 1
  body_hygiene "$(body_of 1)" || return 1
  local week2; week2="$(cmt github-actions "$b" | cl)"
  issue OPEN "$CREATED" "$week2"; : > "$MOCKD/calls"; : > "$MOCKD/gatelog"; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$(gate_runs)" -eq 2 ]]'   # only the two clean commits are judged again
}
chk_unj_text() { # WARN and garbage commits: unjudgeable, and the comment never says off-brand colour
  mkrepo; clean "a"; fc apps/web-platform/app/zz-warn.tsx "$TOK_TSX" "warns"; local w="$LAST"
  fc apps/web-platform/app/zz-garbage.tsx "$TOK_TSX" "garbage"; local gb="$LAST"; clean "d"; use_wrapper; run
  local b; b="$(cat "$(body_of 1)" 2>/dev/null)"
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$b" != *"off-brand colour"* && "$b" == *"could not be judged"* ]]' || return 1
  need 'has_sent "$(body_of 1)" "trigger-2-unjudgeable:$w" && has_sent "$(body_of 1)" "trigger-2-unjudgeable:$gb" && [[ "$(nsent "$(body_of 1)" trigger-2:)" -eq 0 ]]'
}
chk_unj_realtimeout() { # a really hanging gate is killed by timeout and reported unjudgeable, fast
  mkrepo; clean "a"; fc apps/web-platform/app/zz-slow.tsx "$TOK_TSX" "hangs"; local s="$LAST"; clean "c"; use_wrapper
  RUN_ENV=(WATCH_GATE_TIMEOUT=1); local t0=$SECONDS; run; local dt=$((SECONDS - t0))
  need '[[ "$RC" -eq 0 && "$dt" -lt 15 && "$(posted)" -eq 1 ]]' && need 'has_sent "$(body_of 1)" "trigger-2-unjudgeable:$s"'
}
chk_sys_garbage() { # the first three judged commits all unusable: systemic, exit 3, nothing posted
  mkrepo; clean; clean; clean; clean; use_wrapper; RUN_ENV=(FIX_FORCE=garbage); run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"::error::"* ]]' && need 'worktrees_clean'
}
chk_sys_warn() { # same for a gate that only ever warns
  mkrepo; clean; clean; clean; use_wrapper; RUN_ENV=(FIX_FORCE=warn); run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]]'
}
chk_pre_nogate() { # no gate file on disk: cannot establish
  mkrepo; assert_fixture_dir "$REPO"; rm -f "$REPO/.claude/hooks/brand-hex-commit-gate.sh"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"brand-hex-commit-gate"* ]]'
}
mkpath() { # mkpath NAME EXCLUDE: a PATH directory of the tools a run needs (symlinks) minus one tool, and no gh
  local d="$ROOT/path-$1" t src; assert_fixture_dir "$d"; mkdir -p "$d" || fatal "mkpath failed"
  for t in bash sh env git jq perl timeout mktemp cat sed grep date tr head tail sort rm mkdir rmdir dirname basename awk cut wc ls readlink cp mv sleep uname id tee xargs find ln chmod touch diff cmp expr; do
    [[ "$t" == "$2" ]] && continue
    src="$(command -v "$t" 2>/dev/null)" || continue
    [[ "$src" == /* ]] && ln -s "$src" "$d/$t" 2>/dev/null
  done
}
chk_pre_noperl() { # perl absent: the lexer-less gate would silently allow; exit 3 instead
  mkrepo; RUN_PATH="$MOCKD:$ROOT/path-noperl"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"perl"* ]]'
}
chk_pre_nojq() {
  mkrepo; RUN_PATH="$MOCKD:$ROOT/path-nojq"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"jq"* ]]'
}
chk_budget() { # the loop budget truncates like the cap
  mkrepo; clean; clean; clean; use_wrapper; RUN_ENV=(FIX_FORCE=slow WATCH_LOOP_BUDGET=1); run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"examined=1 truncated=1 budget=1"* && "$ERR$OUT" == *"::warning::"* ]]'
}
chk_cap() { # more than 200 candidate commits: examined=200 truncated=1, exit 0
  mkrepo; clean "tip-1"; local i f="$MOCKD/fi" tip; tip="$(g rev-parse HEAD)"; : > "$f"
  for i in $(seq 1 201); do
    local content="export const n = $i;" msg="c$i"
    printf 'commit refs/heads/main\ncommitter t <t@t> %s +0000\ndata %s\n%s\n' "$((WIN_T0 + 100000 + i * 60))" "${#msg}" "$msg" >> "$f"
    [[ "$i" -eq 1 ]] && printf 'from %s\n' "$tip" >> "$f"
    printf 'M 100644 inline apps/web-platform/components/cap.tsx\ndata %s\n%s\n\n' "${#content}" "$content" >> "$f"
  done
  g fast-import --quiet < "$f" || fatal "fast-import failed"
  g reset -q --hard || fatal "reset failed"
  use_wrapper; RUN_ENV=(FIX_FORCE=allow); run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"examined=200 truncated=1"* && "$(gate_runs)" -eq 200 ]]' && need 'worktrees_clean'
}

# ---- tracker states, modes, hygiene ----
chk_closed() { mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; offend; issue CLOSED "$CREATED" '[]'; use_wrapper; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"::notice::"* && "$(gate_runs)" -eq 0 ]]'; }
chk_gone() { mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; flag view_gone; run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"::notice::"* && "$OUT" == *"tracker gone"* ]]'; }
chk_readfail() { mkrepo; flag view_fail; run; need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]]'; }
chk_nullcomments() { mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; rawissue "{\"state\":\"OPEN\",\"createdAt\":\"$CREATED\",\"comments\":null}"; run
  need '[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"::error::"* ]]'; }
chk_dry() { # both detectors run, the would-be comment is printed, nothing is posted or spent
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; offend; local sha="$LAST"; run --dry-run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"new-hook.sh"* && "$OUT" == *"${sha:0:12}"* && "$OUT" == *"dry-run: nothing posted"* ]]' && need 'calls_are "$VIEW_ARGV"'
}
chk_print_state() { # local git only: no gh call at all, fast, the documented first line
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; clean; clean; local t0=$SECONDS; run --print-state; local dt=$((SECONDS - t0))
  need '[[ "$RC" -eq 0 && "$dt" -lt 15 && "$(head -n 1 <<<"$OUT")" == "watch=brand-hex-11177 mode=print-state" && "$OUT" == *"new-hook.sh"* && "$OUT" == *"candidates=2"* && ! -s "$MOCKD/calls" ]]'
}
chk_xtrace() { # bash -x with a token in the environment: refuse before anything runs
  mkrepo; assert_fixture_dir "$REPO"
  ( cd "$REPO" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "GH_TOKEN=$DUMMY_TOKEN" bash -x "$SUT_UNDER" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
  RC=$?; ERR="$(cat "$MOCKD/stderr")"; OUT=""
  need '[[ "$RC" -eq 78 && "$ERR" == *"refusing to run under xtrace"* && ! -s "$MOCKD/calls" ]]'
}
chk_usage() { mkrepo; run --nope; need '[[ "$RC" -eq 2 && "$ERR" == *"usage:"* && ! -s "$MOCKD/calls" ]]'; }
chk_hostile() { # hostile subject and paths: inert, no mention, no closing keyword, no marker forgery
  mkrepo
  fc "apps/web-platform/app/@user.tsx" "$OFF_TSX" 'fixes #11177 @octocat <!-- hide --> `tick` resolved owner/repo#5 --> & closes #9'
  fc ".claude/hooks/at@x&y.sh" "$HOOK_SRC" "hostile hook name"; run
  local b; b="$(cat "$(body_of 1)" 2>/dev/null)"
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$b" == *"octocat"* ]]' || return 1
  body_hygiene "$(body_of 1)"
}
chk_env_dry() { # an inherited WN_DRY_RUN=1 without --dry-run must still post
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; RUN_ENV=(WN_DRY_RUN=1); run
  need '[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$OUT" != *"dry-run"* ]]'
}
chk_mockalive() { # the recorder is alive: a posting scenario records a view AND a comment
  mkrepo; fc .claude/hooks/new-hook.sh "$HOOK_SRC" "hook"; run
  need '[[ "$(grep -c "^issue view " "$MOCKD/calls" || true)" -ge 1 && "$(posted)" -ge 1 ]]'
}

# ============================================================== run the checks =====
[[ -s "$SUT" ]] || echo "NOTE: $SUT is missing (RED phase): every scenario below is expected to fail"
mkpath noperl perl; mkpath nojq jq

scenario "G3 clean: no extra hook, nothing posted, trigger 2 reports examined=0" chk_g3_clean
scenario "G3 row1: a new hook sourcing the lib fires once (sentinel last, exact call set)" chk_g3_r1
scenario "G3 row2: a whole-line comment mention does not fire" chk_g3_r2
scenario "G3 row3: the brand-hex gate sourcing the lib (the fix landing) does not fire" chk_g3_r3
scenario "G3 row4: a second extra hook after a first are both listed, a plugin lib file is not" chk_g3_r4
scenario "G3 row5: zero tracked hooks is exit 3, not clean" chk_g3_r5
scenario "G3 harness: .test.sh, lib/, untracked and plugin lib files stay silent" chk_g3_silent
scenario "G3 trigger 1 already notified by the bot: silent" chk_g3_seen
scenario "G2 prefix: bot v10 and human v1 sentinels do not suppress trigger-1:v1" chk_g2_prefix
scenario "G4 row1: a raw hex colour in a UI file is a finding (route caveat, teardown clean)" chk_g4_r1
scenario "G4 row2: token reference and token-definition CSS are not findings" chk_g4_r2
scenario "G4 row3: commits older than the tracker print examined=0 (no vacuous clean)" chk_g4_r3
scenario "G4 row4: two offenders around a compliant commit are both reported" chk_g4_r4
scenario "G4 row6: email class allows a palette hex and flags an off-palette one" chk_g4_r6
scenario "G4 row7: clean/offender/clean in the reused worktree reports exactly the offender" chk_g4_r7
scenario "G4 harness: commits outside the path classes are skipped without running the gate" chk_g4_outside
scenario "G4 first-parent: a merge is judged, the side-branch commit is not listed" chk_g4_merge
scenario "G2 sentineled finding is neither re-run through the gate nor re-posted" chk_sent_skip
scenario "G2 row3: a sentineled newest finding does not hide an older new one" chk_g2_r3
scenario "G2 a human-pasted full sentinel and bot short prefixes do not suppress" chk_g2_human
scenario "G2 harness: the github-actions[bot] spelling suppresses as well" chk_g2_bot_spelling
scenario "G2 row4: unevaluable comments are exit 3, never absent" chk_g2_malformed
scenario "more than 10 findings: ten listed, every finding sentineled, one comment" chk_over10
scenario "a failed post is exit 1" chk_postfail
scenario "G4 row8: one timed-out commit is reported unjudgeable once and never re-run" chk_unj_one
scenario "G4 row8: WARN and garbage commits are unjudgeable and never called off-brand" chk_unj_text
scenario "G4 row8: a really hanging gate is killed by the timeout wrapper" chk_unj_realtimeout
scenario "G4 row9: the first three judged commits unusable (garbage) is exit 3" chk_sys_garbage
scenario "G4 row9: the first three judged commits unusable (WARN) is exit 3" chk_sys_warn
scenario "G4 row9: no gate file is exit 3" chk_pre_nogate
scenario "G4 row9: perl absent is exit 3" chk_pre_noperl
scenario "G4 row9: jq absent is exit 3" chk_pre_nojq
scenario "G4 budget: the loop budget truncates with examined/truncated/budget and a warning" chk_budget
scenario "G4 cap: 201 candidates print examined=200 truncated=1 and exit 0" chk_cap
scenario "tracker CLOSED is a notice and a no-op" chk_closed
scenario "tracker gone (Could not resolve) is a terminal notice" chk_gone
scenario "an unrecognised read error is exit 3" chk_readfail
scenario "null comments are exit 3" chk_nullcomments
scenario "--dry-run runs both detectors, prints the comment, posts nothing" chk_dry
scenario "--print-state is local only, fast, with the documented first line" chk_print_state
scenario "bash -x is refused with exit 78 before anything runs" chk_xtrace
scenario "an unknown argument is exit 2 with usage and no gh call" chk_usage
scenario "hostile third-party text is inert (no mention, keyword, marker forgery)" chk_hostile
scenario "an inherited WN_DRY_RUN=1 without --dry-run still posts" chk_env_dry
scenario "H1 the recorder is alive: a posting scenario logs a view and a comment" chk_mockalive

# ---------------------------------------------------- source facts the checks lean on
sut_active="$(grep -vE '^[[:space:]]*#' "$SUT" 2>/dev/null || true)"
first_code="$(printf '%s\n' "$sut_active" | grep -v '^[[:space:]]*$' | sed -n '1,4p' | tr '\n' ' ')"
xt_line="$(grep -n 'refusing to run under xtrace' "$SUT" 2>/dev/null | head -n 1 | cut -d: -f1)"
src_line="$(grep -nE '^\.[[:space:]]+.*watch-notify-once\.sh|^source[[:space:]]+.*watch-notify-once\.sh' "$SUT" 2>/dev/null | head -n 1 | cut -d: -f1)"
[[ -n "$xt_line" && -n "$src_line" && "$xt_line" -lt "$src_line" ]] \
  && pass "the xtrace refusal sits above the library source line" || fail "xtrace refusal is not above the lib source (xt=$xt_line src=$src_line)"
[[ -x "$SUT" ]] && pass "the script is executable" || fail "the script is not executable"
[[ "$first_code" == *"set -uo pipefail"* && -z "$(grep -E '^[[:space:]]*set +-[a-z]*e' "$SUT" 2>/dev/null || true)" ]] \
  && pass "set -uo pipefail and no errexit" || fail "set -uo pipefail missing or errexit present"
ui_re_src="$(sed -nE 's/^UI_RE="\$\{SOLEUR_BRAND_HEX_UI_RE:-(.*)\}"$/\1/p' "$REAL_HOOKS/brand-hex-commit-gate.sh")"
[[ -n "$ui_re_src" && "$sut_active" != *"$ui_re_src"* ]] \
  && pass "the gate's path classes are derived from its source, not copied into the watcher" || fail "the watcher copies the gate's UI regex or the gate no longer declares it"

# ------------------------------------------------------------- mutation harness ----
MUTN=0
# mutate_in FILE OLD NEW: replace the single occurrence of OLD (fixed string); rc 1 when OLD is absent
# or ambiguous.
mutate_in() {
  OLD="$2" NEW="$3" perl -0777 -i -pe 'BEGIN{ $o=$ENV{OLD}; $n=$ENV{NEW}; } $c = () = /\Q$o\E/g; if ($c != 1) { print STDERR "anchor count=$c\n"; exit 3 } s/\Q$o\E/$n/' "$1" 2>/dev/null
}
# mutation_row ID DESC CHECK FILE-KIND OLD NEW [FILE-KIND OLD NEW ...]
mutation_row() {
  local id="$1" desc="$2" chk="$3"; shift 3
  MUTN=$((MUTN + 1))
  local d="$ROOT/mut$MUTN"; assert_fixture_dir "$d"
  mkdir -p "$d/scripts/lib" || fatal "mut mkdir failed"
  cp "$SUT" "$d/scripts/watch-brand-hex-triggers-11177.sh" && cp "$LIBF" "$d/scripts/lib/watch-notify-once.sh" || fatal "mut copy failed"
  local copy="$d/scripts/watch-brand-hex-triggers-11177.sh"
  SUT_UNDER="$copy"; DIAG=""
  if ! "$chk"; then SUT_UNDER="$SUT"; fail "$id control (unmutated copy) is not green [$DIAG]"; return; fi
  local landed=1 kind old new target
  while [[ "$#" -ge 3 ]]; do
    kind="$1"; old="$2"; new="$3"; shift 3
    case "$kind" in sut) target="$copy" ;; lib) target="$d/scripts/lib/watch-notify-once.sh" ;; *) fatal "bad kind $kind" ;; esac
    mutate_in "$target" "$old" "$new" || landed=0
  done
  local differs=0
  { ! cmp -s "$SUT" "$copy" || ! cmp -s "$LIBF" "$d/scripts/lib/watch-notify-once.sh"; } && differs=1
  if [[ "$landed" -ne 1 || "$differs" -ne 1 ]]; then SUT_UNDER="$SUT"; fail "$id mutation did not land (anchor or cmp) - $desc"; return; fi
  DIAG=""
  if "$chk"; then SUT_UNDER="$SUT"; fail "$id mutated copy stayed GREEN: $desc"; else SUT_UNDER="$SUT"; pass "$id RED under mutation: $desc"; fi
}

if [[ -s "$SUT" ]]; then
  mutation_row "G3-h1" "empty the exclusion list: the gate adopting the lib now fires" chk_g3_r3 \
    sut 'EXCLUDED_HOOKS=(git-commit-secret-scan.sh brand-hex-commit-gate.sh)' 'EXCLUDED_HOOKS=()'
  mutation_row "G3-r2" "drop the comment stripping" chk_g3_r2 \
    sut "noncomment=\"\$(grep -vE '^[[:space:]]*#' <<<\"\$content\")\"" 'noncomment="$content"'
  mutation_row "G3-r4" "stop at the first firing hook" chk_g3_r4 \
    sut 'FIRED+=("$f")' 'FIRED+=("$f"); break'
  mutation_row "G3-r5" "an empty tracked-hook listing reads as clean" chk_g3_r5 \
    sut 'if [[ "${#HOOKS[@]}" -eq 0 ]]; then' 'if false; then'
  mutation_row "G4-h1" "remove the read-tree step: the gate sees an empty diff and allows everything" chk_g4_r1 \
    sut 'git -C "$WT" read-tree "$sha" >/dev/null 2>&1' 'true'
  mutation_row "G4-r7" "refresh the reused worktree index only once" chk_g4_r7 \
    sut 'if git -C "$WT" reset --mixed -q "$parent" >/dev/null 2>&1 && git -C "$WT" read-tree "$sha" >/dev/null 2>&1; then' \
        'if { [[ -n "${ONCE:-}" ]] || { git -C "$WT" reset --mixed -q "$parent" >/dev/null 2>&1 && git -C "$WT" read-tree "$sha" >/dev/null 2>&1; }; }; then ONCE=1'
  mutation_row "G4-r3" "drop the createdAt window" chk_g4_r3 \
    sut '--since="$WN_CREATED"' '--first-parent'
  mutation_row "G4-r5" "read an unusable gate result as allow" chk_unj_text \
    sut '*) verdict=unjudgeable ;;' '*) verdict=allow ;;'
  mutation_row "G4-r8" "an unjudgeable commit is dropped instead of reported" chk_unj_one \
    sut 'UNJ+=("$sha")' ': "$sha"'
  mutation_row "G4-r9" "no systemic exit after three unjudgeable commits" chk_sys_garbage \
    sut '[[ "$judged" -eq 3 && "$unj_count" -eq 3 ]]' 'false'
  mutation_row "G4-perl" "no tool preflight" chk_pre_noperl \
    sut 'wn_preflight || exit 3' 'true'
  mutation_row "G4-budget" "no loop budget" chk_budget \
    sut '[[ "$(( SECONDS - loop_start ))" -ge "$BUDGET" ]]' 'false'
  mutation_row "G2-r1" "do not skip a sentineled commit (re-run and re-post)" chk_sent_skip \
    sut 'skipped=$((skipped + 1)); continue; fi' 'skipped=$((skipped + 1)); fi'
  mutation_row "G2-r3" "stop at the first sentineled commit" chk_g2_r3 \
    sut 'skipped=$((skipped + 1)); continue; fi' 'skipped=$((skipped + 1)); break; fi'
  mutation_row "G2-r2" "accept any comment author in the sentinel reader (lib)" chk_g2_human \
    lib '(.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]"' 'true'
  mutation_row "G2-r4" "a jq failure in the sentinel reader reads as absent (lib)" chk_g2_malformed \
    lib '2>/dev/null)" || return 3
  [[ "$count" =~ ^[0-9]+$ ]] || return 3' '2>/dev/null)" || true
  [[ "$count" =~ ^[0-9]+$ ]] || return 1'
  mutation_row "G2-h" "remove the wn_post call: the posting scenarios must go RED" chk_g4_r1 \
    sut 'wn_post "$ISSUE"' 'cat >/dev/null'
  mutation_row "G1-r1" "dry-run guard removed: --dry-run posts" chk_dry \
    sut 'if [[ "$WN_DRY_RUN" == 1 ]]; then' 'if false; then'
  mutation_row "G1-r1b" "the inherited WN_DRY_RUN is no longer reset after sourcing the lib" chk_env_dry \
    sut 'WN_DRY_RUN=0' ':'
  mutation_row "G1-r2" "tracker state check removed: a CLOSED tracker is commented on" chk_closed \
    sut '[[ "$WN_STATE" != "OPEN" ]]' 'false'
  # G1 row 2 (the recorder goes dead): a posting scenario must notice the empty call log.
  MOCK_DEAD=0; DIAG=""
  if chk_g3_r1; then
    MOCK_DEAD=1; DIAG=""
    if chk_g3_r1; then fail "G1-r2b a dead recorder stayed GREEN"; else pass "G1-r2b RED when the recording gh logs nothing (call-count floor)"; fi
    MOCK_DEAD=0
  else
    fail "G1-r2b control is not green [$DIAG]"
  fi
else
  fail "mutation matrix skipped: $SUT is missing"
fi

# ------------------------------------------------------------ recorded-argv oracle ----
bad=0; seen=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  while IFS= read -r line; do
    seen=$((seen + 1))
    case "$line" in "issue view "*|"issue comment "*) ;; *) bad=$((bad + 1)); echo "unexpected call: $line" ;; esac
  done < "$d/calls"
done
[[ "$bad" -eq 0 && "$seen" -gt 0 ]] && pass "recorded gh argv set is a subset of {issue view, issue comment} ($seen calls)" || fail "recorded argv oracle ($bad unexpected of $seen)"

# ------------------------------------------------------------ workflow facets ----
if [[ -f "$WF" ]]; then
  PYF="$ROOT/wf-facets.py"
  cat > "$PYF" <<'PY'
import re, sys
try:
    import yaml
except Exception:
    print("SKIP-NO-YAML"); sys.exit(0)
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
doc = yaml.safe_load(text)
missing = []
on = doc.get("on", doc.get(True, {})) or {}
crons = [s.get("cron") for s in (on.get("schedule") or [])]
if "17 9 * * 1" not in crons: missing.append("cron")
disp = on.get("workflow_dispatch") or {}
if "dry_run" not in ((disp or {}).get("inputs") or {}): missing.append("dispatch-input")
active = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
if "secrets." in active: missing.append("secrets-reference")
top = doc.get("permissions")
if top not in ({}, None, {"contents": "read"}): missing.append("top-permissions")
jobs = doc.get("jobs") or {}
if not jobs: missing.append("no-jobs")
script = "watch-brand-hex-triggers-11177.sh"
found = False
for name, job in jobs.items():
    cond = str(job.get("if", ""))
    if "default_branch" not in cond: missing.append("if-guard:" + name)
    if job.get("permissions") != {"contents": "read", "issues": "write"}: missing.append("permissions:" + name)
    steps = job.get("steps") or []
    for st in steps:
        if "actions/checkout" in str(st.get("uses", "")):
            w = st.get("with") or {}
            if str(w.get("persist-credentials")).lower() != "false": missing.append("persist-credentials:" + name)
    runs = [str(st.get("run", "")) for st in steps]
    for r in runs:
        if re.search(r"\$\{\{[^}]*dry_run", r): missing.append("dry_run-interpolated-in-run:" + name)
    if any(script in r for r in runs):
        found = True
        co = [st for st in steps if "actions/checkout" in str(st.get("uses", ""))]
        if not co or any(str((st.get("with") or {}).get("fetch-depth")) != "0" for st in co): missing.append("fetch-depth-0:" + name)
        envs = [job.get("env") or {}] + [st.get("env") or {} for st in steps]
        if not any("dry_run" in str(v) for e in envs for v in e.values()): missing.append("dry_run-env:" + name)
if not found: missing.append("job-for-script-3")
print("OK" if not missing else "MISSING " + " ".join(missing))
PY
  wf_res="$(python3 -I "$PYF" "$WF" 2>&1)"
  case "$wf_res" in
    SKIP-NO-YAML) pass "workflow facets: skipped (PyYAML unavailable) - PASS-skip" ;;
    OK) pass "workflow facets: cron, default-branch if guards, exact permissions, no secrets, fetch-depth 0, persist-credentials false, dry_run via env" ;;
    *) fail "workflow facets: $wf_res" ;;
  esac
else
  pass "workflow facets: skipped, $WF does not exist yet - PASS-skip"
fi

# Exit-gate check (behavioural): this same suite, re-run with ONE injected failure, must exit
# EXACTLY 1. An `exit 0` placed before the gate, a reset FAIL counter, or a neutered exit path
# would all give 0 here; the FATAL below runs before any of them can.
if [[ -z "${WBH_INJECT_FAIL:-}" ]]; then
  wait "$nested_pid"; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: the exit gate returned %s (expected 1) with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
# Anti-vacuity floor (ADR-193). The threshold is declared on the line IMMEDIATELY above the
# `if`, not with the other constants: guard-vacuity-floor builds its mutant by slicing the floor
# block plus the CONTIGUOUS simple assignments above it.
MIN_ASSERTIONS=65
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
finish || exit 1
