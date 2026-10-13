#!/usr/bin/env bash
# Matrix for scripts/lib/trusted-verdict.sh (Guard 2).
#
# WHY IT LIVES BESIDE THE LIB AND NOT INSIDE A CONSUMER. Ten sibling libs follow
# that convention, and a consumer-housed test dies when its tracker closes — which
# is exactly what this PR does to the #6617 probe. The lib outlives any one probe,
# so its matrix must too.
#
# THE `gh` STUB REFUSES ARGV IT DID NOT EXPECT (exit 64). A stub that answers the
# same fixture regardless of its arguments puts the fixture seam ABOVE the code
# under test: it cannot detect the SUT asking the WRONG question (the wrong issue,
# the wrong login, the wrong endpoint), so the request shape ships unpinned. Every
# unexpected invocation is also echoed to stderr and reddens the case.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/trusted-verdict.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

# canonical fixture-dir guard (the one ci-push-dedupe-soak-9512.test.sh carries): the rows added by the review call it before a write
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; a write under it would retarget %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- instrument self-test -----------------------------------------------------
# Drive both verdict helpers once each and refuse to continue unless BOTH counters
# moved. A suite whose helpers are neutered reports a clean run having asserted
# nothing; this is the only thing upstream of every assertion below.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_FAILS=1    # proven by the check immediately above (PASS==1 and FAIL==1 there)
FAIL=$(( FAIL - SELFTEST_FAILS ))   # the self-test failure is not a real finding

echo "=== scripts/lib/trusted-verdict.sh ==="

# --- harness -----------------------------------------------------------------
# Builds a sandbox with a `gh` stub on PATH, seeded from two files:
#   comments.json  — the `gh issue view --json comments` payload
#   perms          — `login<TAB>permission` lines; a permission of `403` makes the
#                    stub exit non-zero for that login (the API-error arm)
SB="$(mktemp -d "${TMPDIR%/}/trusted-verdict.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" || { echo "mkdir failed" >&2; exit 2; }

cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Refuses any invocation it was not built to answer, and LOGS every refusal to
# $STUB_REFUSED before exiting 64. The lib sends `gh issue view` stderr to /dev/null
# and `gh api` stderr to a tmpfile, so without the log a refused argv is
# indistinguishable from a transient failure and an rc-2 row would pass for the wrong
# reason. $STUB_LOG records every request that WAS answered (`issue <n>` / `perm <login>`).
set -uo pipefail
refuse() { printf 'REFUSED %s\n' "$*" >> "$STUB_REFUSED"; printf 'STUB-UNEXPECTED: gh %s\n' "$*" >&2; exit 64; }
case "${1:-}" in
  issue)
    # exactly: issue view <n> --repo <repo> --json comments --jq <expr>
    [[ $# -eq 9 && "${2:-}" == view && "${3:-}" == "$STUB_EXPECT_ISSUE" && "${4:-}" == --repo \
       && "${5:-}" == "$STUB_EXPECT_REPO" && "${6:-}" == --json && "${7:-}" == comments \
       && "${8:-}" == --jq && -n "${9:-}" ]] || refuse "$@"
    printf 'issue %s\n' "$3" >> "$STUB_LOG"
    jq -r "$9" < "$STUB_COMMENTS"
    ;;
  api)
    # exactly: api repos/<repo>/collaborators/<login>/permission --jq <expr>  (a call with no --jq is refused)
    ep="${2:-}"
    [[ $# -eq 4 && "$ep" == repos/"$STUB_EXPECT_REPO"/collaborators/*/permission && "${3:-}" == --jq && -n "${4:-}" ]] || refuse "$@"
    login="${ep#repos/"$STUB_EXPECT_REPO"/collaborators/}"; login="${login%/permission}"
    printf 'perm %s\n' "$login" >> "$STUB_LOG"
    perm="$(awk -F'\t' -v l="$login" '$1==l{print $2}' "$STUB_PERMS")"
    if [[ -z "$perm" ]]; then printf 'gh: no stub permission for %s\n' "$login" >&2; exit 1; fi
    if [[ "$perm" == "403" ]]; then printf 'gh: Resource not accessible by integration (HTTP 403)\n' >&2; exit 1; fi
    if [[ "$perm" == "404" ]]; then printf 'gh: %s is not a user (HTTP 404)\n' "$login" >&2; exit 1; fi
    printf '{"permission":"%s"}\n' "$perm" | jq -r "$4"
    ;;
  *) refuse "$@" ;;
esac
STUB
chmod +x "$SB/bin/gh"

# The library under test. A mutant row sets LIB_UNDER to a mutated COPY; every other row reads the real lib.
LIB_UNDER=""
REAL_JQ="$(command -v jq)" || { echo "jq is required" >&2; exit 2; }
REAL_AWK="$(command -v awk)" || { echo "awk is required" >&2; exit 2; }
REAL_B64="$(command -v base64)" || { echo "base64 is required" >&2; exit 2; }
XENV=()      # extra KEY=VALUE pairs for the exported environment of the next run_case_raw
INJECT=""    # shell text evaluated in the run AFTER the lib is sourced (a failure injected into a bash builtin or a lib function)
# a bash-level error in the lib under test (a mutant that CRASHES reddens every row, which proves nothing about the guard it removed)
CRASH_RE='syntax error|command not found|unbound variable|bad substitution|unexpected EOF'
note_crash() { assert_fixture_dir "$SB"; if grep -qE "$CRASH_RE" "$SB/err.log" 2>/dev/null; then : > "$SB/crashed"; fi; }
stub_env() { # <issue> <comments-json-file> <perms-file>   (resets the request and refusal logs)
  assert_fixture_dir "$SB"; : > "$SB/req.log"; : > "$SB/refused.log"
  STUB_ENV=(PATH="${STUB_BIN:-$SB/bin}:$PATH" STUB_COMMENTS="$2" STUB_PERMS="$3" STUB_EXPECT_ISSUE="$1" STUB_EXPECT_REPO="${REPO_EXP:-jikig-ai/soleur}"
            STUB_LOG="$SB/req.log" STUB_REFUSED="$SB/refused.log" INJECT="${INJECT:-}" "${XENV[@]}")
}

# run_case <name> <issue> <comments-json-file> <perms-file>
#   echoes: "<rc>|<stdout>"   (stdout only when rc is 0: the historical contract of rows 1-9)
run_case() {
  local issue="$1" cjson="$2" pfile="$3" out rc
  stub_env "$issue" "$cjson" "$pfile"
  out="$(
    env "${STUB_ENV[@]}" bash -c '
      set -uo pipefail
      # shellcheck disable=SC1090
      source "$1"
      if bodies="$(trusted_verdict_bodies "$2")"; then
        printf "%s" "$bodies"
        exit 0
      else
        exit 2
      fi
    ' _ "${LIB_UNDER:-$LIB}" "$issue" 2>"$SB/err.log"
  )"; rc=$?
  note_crash
  if grep -q 'STUB-UNEXPECTED' "$SB/err.log" || [[ -s "$SB/refused.log" ]]; then
    printf 'STUBMISS|%s' "$(head -1 "$SB/refused.log")"
    return
  fi
  printf '%s|%s' "$rc" "$out"
}

# run_case_raw <view function> <issue> <comments-json-file> <perms-file> [repo]
#   Records the view's rc and its stdout INDEPENDENTLY (run_case discards stdout on a
#   nonzero rc, which would hide the "rc 2 must leave NO partial output" property).
#   Sets RAW_RC, RAW_OUT, RAW_MISS (1 when the stub refused an argv).
RAW_RC=""; RAW_OUT=""; RAW_MISS=0
run_case_raw() {
  local view="$1" issue="$2" cjson="$3" pfile="$4" repoarg="${5:-}"
  stub_env "$issue" "$cjson" "$pfile"
  env "${STUB_ENV[@]}" bash -c '
      set -uo pipefail
      # shellcheck disable=SC1090
      source "$1"
      if [[ -n "${INJECT:-}" ]]; then eval "$INJECT"; fi
      "$2" "$3" ${6:+"$6"} >"$4"
      echo "$?" >"$5"
    ' _ "${LIB_UNDER:-$LIB}" "$view" "$issue" "$SB/raw.out" "$SB/raw.rc" "$repoarg" 2>"$SB/err.log"
  note_crash
  RAW_RC="$(cat "$SB/raw.rc" 2>/dev/null || echo none)"; RAW_OUT="$(cat "$SB/raw.out" 2>/dev/null)"
  RAW_MISS=0; if grep -q 'STUB-UNEXPECTED' "$SB/err.log" || [[ -s "$SB/refused.log" ]]; then RAW_MISS=1; fi
}
nreq() { grep -c "^$1 " "$SB/req.log" || true; }   # <issue|perm>: how many requests of that kind the stub answered

mkcomments() { printf '%s\n' "$1" > "$SB/c.json"; echo "$SB/c.json"; }
mkperms()    { printf '%s\n' "$1" > "$SB/p.tsv"; echo "$SB/p.tsv"; }

# `verdict <bodies>` mirrors the consumers' own last-verdict-wins rule, so the
# matrix scores the same thing a probe would.
verdict() { printf '%s\n' "$1" | grep -E '^RESULT: (PASS|FAIL)\b' | tail -1; }

# --- Row 1: PASS from an untrusted login ---------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"drive-by"},"authorAssociation":"CONTRIBUTOR","body":"RESULT: PASS"}]}')"
p="$(mkperms 'drive-by\tread')"
p="$SB/p.tsv"; printf 'drive-by\tread\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "row 1: RESULT: PASS from a login with permission=read yields NO verdict (probe cannot exit 0)"
else
  fail "row 1: expected rc=0 with no verdict; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 2: the measured #6617 shape -------------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"authorAssociation":"CONTRIBUTOR","body":"RESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 6617 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: PASS" ]]; then
  pass "row 2: authorAssociation=CONTRIBUTOR + permission=admin IS honoured (the #6617 shape)"
else
  fail "row 2: expected rc=0 and RESULT: PASS; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 3: two trusted comments, PASS then FAIL -------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"},{"author":{"login":"deruelle"},"body":"RESULT: FAIL"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: FAIL" ]]; then
  pass "row 3: last trusted verdict wins (PASS then FAIL -> FAIL)"
else
  fail "row 3: expected rc=0 and RESULT: FAIL; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 4: permission read fails (403) ----------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}')"
printf 'deruelle\t403\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "row 4: a 403 on the permission read yields TRANSIENT (rc=2), never PASS"
else
  fail "row 4: expected rc=2 (TRANSIENT); got rc=$rc"
fi

# --- Row 7 (must-PASS, non-canonical): leading blank line before the verdict ----
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"\nRESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: PASS" ]]; then
  pass "row 7 (must-PASS): a leading blank line before RESULT: PASS is still honoured"
else
  fail "row 7: expected rc=0 and RESULT: PASS; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Fenced blocks cannot arm a probe ------------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"see the template:\n```\nRESULT: PASS\n```\nnot a verdict"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "a RESULT: line inside a fenced block is stripped and cannot arm the probe"
else
  fail "fenced-block strip: expected no verdict; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- HARNESS INTEGRITY: an author-less fixture must FAIL LOUDLY -----------------
# A fixture with no author cannot exercise the filter at all — it must not quietly
# pass as "no verdict". That is the exact defect #7448's learning file records.
c="$(mkcomments '{"comments":[{"authorAssociation":"OWNER","body":"RESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "harness integrity: an author-less comment is dropped and can never carry a verdict"
else
  fail "harness integrity: an author-less comment reached the verdict grep (rc=$rc verdict='$(verdict "$body")')"
fi

# --- Row 4b: a 404 on the permission read is DEFINITIVE, not transient ---------
# `github-actions` comments on nearly every tracker and GitHub answers
# `"github-actions is not a user" (HTTP 404)` for it. Collapsing that into TRANSIENT
# makes every thread with a bot comment permanently unresolvable — measured against
# live #6617 on 2026-09-19, the first build of this lib did exactly that and returned
# rc=2. Both directions are fixtured: the bot must be DROPPED while the trusted
# author's verdict still comes through.
c="$(mkcomments '{"comments":[{"author":{"login":"github-actions"},"body":"RESULT: PASS"},{"author":{"login":"deruelle"},"body":"RESULT: FAIL"}]}')"
printf 'github-actions\t404\nderuelle\tadmin\n' > "$p"
r="$(run_case 6617 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: FAIL" ]]; then
  pass "row 4b: a 404 ('not a user') drops that author without wedging the read into TRANSIENT"
else
  fail "row 4b: expected rc=0 and RESULT: FAIL from the trusted author; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 4c: the 404 arm must not swallow a 403 --------------------------------
# The discriminator added for row 4b is a branch on the error TEXT, so it needs a
# fixture on the OTHER side too: a 403 must still be TRANSIENT even though it takes
# the same `gh api` non-zero path.
c="$(mkcomments '{"comments":[{"author":{"login":"github-actions"},"body":"noise"},{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}')"
printf 'github-actions\t404\nderuelle\t403\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "row 4c: a 403 is still TRANSIENT — the 404 arm did not widen into every error"
else
  fail "row 4c: expected rc=2 (TRANSIENT); got rc=$rc"
fi

# --- The comment read itself failing is TRANSIENT ------------------------------
r="$(run_case 5733 "$SB/does-not-exist.json" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "a failed comment read yields TRANSIENT (rc=2), not 'no verdict, therefore fine'"
else
  fail "failed comment read: expected rc=2; got rc=$rc"
fi

# --- row 8: BOTH fence spellings are stripped ---------------------------------
# The strip exists so a quoted template in a trusted author's comment cannot arm the
# probe. It matched ``` only, so the CommonMark-equivalent ~~~ fence was a live
# channel for exactly that — and it is a TRUSTED author's comment, so the fixture
# below is the realistic shape (someone pasting the convention into the tracker),
# not an attack. Both spellings are driven, because fixing one and asserting one
# proves nothing about the other.
cat > "$SB/fenced-both.json" <<'JSON'
{"comments":[{"author":{"login":"deruelle"},"body":"here is the template:\n```\nRESULT: PASS\n```\nand the other spelling:\n~~~\nRESULT: PASS\n~~~\nnot a verdict either way"}]}
JSON
printf 'deruelle\tadmin\n' > "$SB/perms-fence"
r="$(run_case 5733 "$SB/fenced-both.json" "$SB/perms-fence")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" ]] && ! grep -q 'RESULT: PASS' <<<"$body"; then
  pass "row 8: both backtick and tilde fenced blocks are stripped — neither spelling can arm the probe"
else
  fail "row 8: expected rc=0 with no RESULT: PASS surviving; got rc=$rc body=[$body]"
fi

# --- row 9 (MUTATION): an unresolved author is TRANSIENT, never a silent drop ---
# Pass 2 resolves exactly the author set pass 3 reads, so a memo MISS is unreachable
# in the shipped lib. That is why it needs a mutation rather than a fixture: the
# original code said `*) continue ;;`, which merges "resolved as untrusted" with
# "never resolved at all" — the collapse this lib's own header forbids, at the one
# place the header did not assert it. Neuter pass 2's resolver call AND the logincount
# conservation check (which would otherwise answer first, with its own message) and require
# the absent-memo guard itself to REFUSE, by its own stderr text, rather than quietly return
# a shorter list.
MUT="$SB/trusted-verdict-no-resolve.sh"
sed -e 's|^    if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then|    if false; then|' \
    -e 's|_trusted_verdict_stage_fail logincount "$issue"; return 2;|true;|' "$LIB" > "$MUT"
if diff -q "$LIB" "$MUT" >/dev/null || ! grep -q '^    if false; then$' "$MUT" || grep -q 'stage_fail logincount' "$MUT"; then
  fail "row 9: the resolver-call or logincount marker is absent from the lib — the mutation did not land and this row is vacuous"
else
  cat > "$SB/one-verdict.json" <<'JSON'
{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}
JSON
  printf 'deruelle\tadmin\n' > "$SB/perms-mut"
  stub_env 5733 "$SB/one-verdict.json" "$SB/perms-mut"
  mout="$(
    env "${STUB_ENV[@]}" bash -c 'set -uo pipefail; source "$1"; trusted_verdict_bodies "$2" >/dev/null 2>"$3"; echo $?' _ "$MUT" 5733 "$SB/row9.err"
  )"
  if [[ "$mout" == "2" ]] && grep -q 'no memoized permission' "$SB/row9.err"; then
    pass "row 9 MUTATION: an author with no memoized permission yields TRANSIENT (rc=2) from the absent-memo guard itself, not a silent drop"
  else
    fail "row 9 MUTATION: expected rc=2 and the 'no memoized permission' refusal from the un-resolved author; got rc=$mout err=[$(head -c 200 "$SB/row9.err")]"
  fi
fi

# =====================================================================================
# THE TWO-VIEW MATRIX (rows M-H1 .. M-H11, M-NOSLICE and the review rows M-BIG .. M-READONLY). Each row is a FUNCTION so a lib mutant (below) can
# re-run it against a mutated copy. Every negative assertion has a POSITIVE TWIN on the same
# input that differs only in the stubbed permission (an over-trusting or under-trusting
# mutant is then visible from both sides). Every comment carries a CONTRIBUTOR authorAssociation
# DECOY (the private-member shape) so a lib that consulted the association would redden M-H1.
# =====================================================================================
T1="2026-10-11T09:43:23Z"; T2="2026-10-11T09:48:17Z"
mkc() { # <file> then <login> <body> <createdAt|-> triples; `-` omits createdAt; ASSOC overrides the decoy association
  local f="$1"; shift; local -a a=()
  while (( $# )); do
    a+=("$(jq -nc --arg l "$1" --arg b "$2" --arg t "$3" --arg c "${ASSOC:-CONTRIBUTOR}" \
        '{author:{login:$l},authorAssociation:$c,body:$b} + (if $t == "-" then {} else {createdAt:$t} end)')")
    shift 3
  done
  assert_fixture_dir "$f"
  printf '{"comments":[%s]}\n' "$(IFS=,; printf '%s' "${a[*]}")" > "$f"
}
mkp() { assert_fixture_dir "$SB"; printf "$1" > "$SB/pm.tsv"; }   # printf format with literal \t and \n
bodies_of() { jq -r '.b' <<<"$1"; }
# in_out <needle> -> 0 when the {t,b} stream in RAW_OUT carries a body line equal to needle
in_out() { bodies_of "$RAW_OUT" | grep -qxF -- "$1"; }

h_h1() { # M-H1 the repro: a CONTRIBUTOR-association admin author IS trusted
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out "S2-ACTIVATED: $T2"; then
    pass "M-H1: a CONTRIBUTOR-association author with permission=admin is trusted in the {t,b} view"
  else fail "M-H1: rc=$RAW_RC miss=$RAW_MISS out=[$RAW_OUT]"; fi
}
h_h2() { # M-H2 an OWNER-association author whose permission is `read` is NOT trusted; the twin differs only in the permission
  ASSOC=OWNER mkc "$SB/h.json" ownread-op "S2-ACTIVATED: $T2" "$T2"
  mkp 'ownread-op\tread\n'; run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  local neg_ok=0; if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && ! in_out "S2-ACTIVATED: $T2"; then neg_ok=1; fi
  mkp 'ownread-op\tadmin\n'; run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( neg_ok )) && (( RAW_MISS == 0 )) && in_out "S2-ACTIVATED: $T2"; then
    pass "M-H2: OWNER association + permission=read is dropped, the same comment with permission=admin is kept"
  else fail "M-H2: negative arm ok=$neg_ok; twin rc=$RAW_RC out=[$RAW_OUT]"; fi
}
h_h3() { # M-H3 admin/maintain/write trusted; triage is not
  local perm ok=1 got want
  for perm in admin maintain write triage; do
    mkc "$SB/h.json" lvl-op "S2-ACTIVATED: $T2" "$T2"; mkp "lvl-op\\t$perm\\n"
    run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
    got=0; (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out "S2-ACTIVATED: $T2" && got=1
    want=1; [[ "$perm" == triage ]] && want=0
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 ]] || (( got != want )); then ok=0; fail "M-H3: permission=$perm trusted=$got want=$want (rc=$RAW_RC miss=$RAW_MISS)"; fi
  done
  (( ok )) && pass "M-H3: admin, maintain and write are trusted; triage is not"
}
fence_fixture() { mkc "$SB/hf.json" priv-op $'intro\n```\nS2-ACTIVATED: 2026-10-11T00:00:00Z\n```\n~~~\nS2-EXIT-CENSUS: https://github.com/x/y\n~~~\nS2-DEACTIVATED: 2026-10-12T00:00:00Z' "$T1" priv-op $'plain\nS2-EXIT-CENSUS: https://github.com/a/b' "$T2"; mkp 'priv-op\tadmin\n'; }
h_h4_parity() { # M-H4 parity: the bodies view equals the .b projection of the {t,b} view
  fence_fixture
  run_case_raw trusted_verdict_comments 9818 "$SB/hf.json" "$SB/pm.tsv"; local viewb; viewb="$(bodies_of "$RAW_OUT")"; local m1=$RAW_MISS
  run_case_raw trusted_verdict_bodies 9818 "$SB/hf.json" "$SB/pm.tsv"
  if (( m1 == 0 && RAW_MISS == 0 )) && [[ "$RAW_OUT" == "$viewb" && -n "$viewb" ]]; then
    pass "M-H4: trusted_verdict_bodies equals the .b projection of trusted_verdict_comments on one fixture"
  else fail "M-H4 parity: bodies=[$RAW_OUT] view=[$viewb]"; fi
}
h_h4_abs() { # M-H4 ABSOLUTE: a fenced marker (both spellings) is absent from the {t,b} output; the unfenced ones are present
  fence_fixture
  run_case_raw trusted_verdict_comments 9818 "$SB/hf.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && ! in_out 'S2-ACTIVATED: 2026-10-11T00:00:00Z' && ! bodies_of "$RAW_OUT" | grep -q 'x/y' \
     && in_out 'S2-DEACTIVATED: 2026-10-12T00:00:00Z' && in_out 'S2-EXIT-CENSUS: https://github.com/a/b'; then
    pass "M-H4: markers inside backtick and tilde fences are stripped from the {t,b} view, unfenced ones survive"
  else fail "M-H4 absolute: rc=$RAW_RC out=[$RAW_OUT]"; fi
}
h_h5() { # M-H5 t is createdAt byte-for-byte; a missing or non-ISO createdAt is rc 2 with empty stdout in the {t,b} view only
  mkp 'priv-op\tadmin\n'
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  local ok=1 t; t="$(jq -r '.t' <<<"$RAW_OUT")"
  [[ "$RAW_RC" == 0 && "$t" == "$T2" ]] || { ok=0; fail "M-H5: t=[$t] want [$T2] (rc=$RAW_RC)"; }
  local bad
  for bad in yesterday "2026-10-11T09:48:17+02:00" "2026-10-11 09:48:17" "-"; do
    mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$bad"
    run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 2 || -n "$RAW_OUT" ]]; then ok=0; fail "M-H5: createdAt=[$bad] must be rc 2 with empty stdout, got rc=$RAW_RC out=[$RAW_OUT]"; fi
  done
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "-"
  run_case_raw trusted_verdict_bodies 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || "$RAW_OUT" != "S2-ACTIVATED: $T2" ]]; then ok=0; fail "M-H5: the bodies view must not need createdAt (rc=$RAW_RC out=[$RAW_OUT])"; fi
  (( ok )) && pass "M-H5: t is createdAt verbatim; missing/non-ISO createdAt is rc 2 with empty stdout in the {t,b} view; the bodies view does not need it"
}
h_h6() { # M-H6 a failing permission read on the LAST of several authors is rc 2 with EMPTY stdout, for both views; the twin succeeds
  local view ok=1
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    mkc "$SB/h.json" a-op "RESULT: PASS" "$T1" b-op "note" "$T1" c-op "RESULT: FAIL" "$T2"
    mkp 'a-op\tadmin\nb-op\tadmin\nc-op\t403\n'
    run_case_raw "$view" 5733 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 2 || -n "$RAW_OUT" ]]; then ok=0; fail "M-H6 ($view): last author 403 must be rc 2 + empty stdout, got rc=$RAW_RC out=[$RAW_OUT]"; fi
    mkp 'a-op\tadmin\nb-op\tadmin\nc-op\tadmin\n'
    run_case_raw "$view" 5733 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || -z "$RAW_OUT" ]]; then ok=0; fail "M-H6 twin ($view): all-admin must succeed, got rc=$RAW_RC"; fi
  done
  (( ok )) && pass "M-H6: a permission failure on the last of several distinct authors yields rc 2 and NO partial output (both views); the all-admin twin succeeds"
}
h_h7() { # M-H7 a 404 drops that author only; a second trusted author after a compliant first still comes through
  mkc "$SB/h.json" github-actions "RESULT: PASS" "$T1" first-op "first" "$T1" second-op "second" "$T2"
  mkp 'github-actions\t404\nfirst-op\tadmin\nsecond-op\twrite\n'
  run_case_raw trusted_verdict_comments 6617 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out first && in_out second && ! in_out 'RESULT: PASS'; then
    pass "M-H7: a 404 drops only that author; two trusted authors after it both come through"
  else fail "M-H7: rc=$RAW_RC out=[$RAW_OUT]"; fi
}
h_h8() { # M-H8 the memo: two comments by one author cost one permission request; two distinct authors cost two
  mkc "$SB/h.json" same-op "one" "$T1" same-op "two" "$T1" same-op "three" "$T2"; mkp 'same-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"; local n1; n1="$(nreq perm)"
  mkc "$SB/h.json" same-op "one" "$T1" other-op "two" "$T1" same-op "three" "$T2"; mkp 'same-op\tadmin\nother-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"; local n2; n2="$(nreq perm)"
  if (( RAW_MISS == 0 )) && [[ "$n1" == 1 && "$n2" == 2 ]]; then
    pass "M-H8: one permission request per distinct author (3 comments by one author -> 1; two authors -> 2)"
  else fail "M-H8: requests n1=$n1 (want 1) n2=$n2 (want 2)"; fi
}
h_noslice() { # M-NOSLICE the lib's own jq does not slice a long comment list: 150 comments in, 150 out (gh's paging is measured 220/220 on #9777, never modelled by this stub)
  local i body c=()
  for ((i = 1; i <= 150; i++)); do body="n$i"; (( i == 130 )) && body="S2-DEACTIVATED: $T2"; c+=(many-op "$body" "$T1"); done
  mkc "$SB/h.json" "${c[@]}"; mkp 'many-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$(wc -l <<<"$RAW_OUT")" -eq 150 ]] && in_out "S2-DEACTIVATED: $T2"; then
    pass "M-NOSLICE: a 150-comment list through the lib is returned whole, the marker at position 130 included (the lib does not slice; gh paging is not modelled here)"
  else fail "M-NOSLICE: rc=$RAW_RC lines=$(wc -l <<<"$RAW_OUT")"; fi
}
h_h10() { # M-H10 exactly one `gh issue view` per view invocation
  mkc "$SB/h.json" priv-op "x" "$T1"; mkp 'priv-op\tadmin\n'
  local view n ok=1
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"; n="$(nreq issue)"
    if (( RAW_MISS != 0 )) || [[ "$n" != 1 ]]; then ok=0; fail "M-H10 ($view): $n issue-view request(s), want exactly 1 (miss=$RAW_MISS)"; fi
  done
  (( ok )) && pass "M-H10: each view issues exactly one comment read"
}
h_crlf() { # must-PASS non-canonical: digits and interior hyphens in the login, CRLF line endings in the body
  mkc "$SB/h.json" a1-b2-op $'activated\r\nS2-ACTIVATED: '"$T2"$'\r' "$T2"; mkp 'a1-b2-op\twrite\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && bodies_of "$RAW_OUT" | tr -d '\r' | grep -qxF "S2-ACTIVATED: $T2"; then
    pass "must-PASS: a login with digits and interior hyphens and a CRLF body is kept (the caller strips the CR)"
  else fail "CRLF: rc=$RAW_RC out=[$RAW_OUT]"; fi
}
h_h11() { # M-H11 login-shape guard: a login that is not a GitHub login is untrusted with ZERO permission requests; only that author is dropped
  mkc "$SB/h.json" "a/../b" "evil1" "$T1" "x?y" "evil2" "$T1" $'line1\nline2' "evil3" "$T1" "-lead" "evil4" "$T1" good-op "good" "$T2"
  mkp 'a/../b\tadmin\nx?y\tadmin\nline1\tadmin\nline2\tadmin\n-lead\tadmin\ngood-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$(nreq perm)" == 1 ]] && grep -qxF 'perm good-op' "$SB/req.log" \
     && in_out good && ! bodies_of "$RAW_OUT" | grep -q evil; then
    pass "M-H11: malformed logins (path, query, newline, leading dash) make zero permission requests and drop only their own comments"
  else fail "M-H11: rc=$RAW_RC miss=$RAW_MISS requests=[$(tr '\n' ',' < "$SB/req.log")] out=[$RAW_OUT]"; fi
}
h_big() { # M-BIG a trusted body past the ~128 KiB single-argv limit is kept whole (marker included) by BOTH views, never dropped with rc 0
  assert_fixture_dir "$SB"
  { printf 'S2-ACTIVATED: %s\n' "$T2"; head -c 200000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$SB/big.body"
  jq -nc --rawfile b "$SB/big.body" --arg t "$T2" '{comments:[{author:{login:"priv-op"},authorAssociation:"CONTRIBUTOR",body:$b,createdAt:$t}]}' > "$SB/h.json"
  mkp 'priv-op\tadmin\n'
  local view ok=1 first   # not `in_out`: `grep -q` exits at the first line and SIGPIPEs the writer of a 200 KB body under pipefail
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if [[ "$view" == trusted_verdict_comments ]]; then first="$(jq -r '.b' <<<"$RAW_OUT" | sed -n 1p)"; else first="$(sed -n 1p <<<"$RAW_OUT")"; fi
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 ]] || [[ "$first" != "S2-ACTIVATED: $T2" ]] || (( ${#RAW_OUT} < 200000 )); then
      ok=0; fail "M-BIG ($view): rc=$RAW_RC miss=$RAW_MISS first=[${first:0:40}] out-bytes=${#RAW_OUT} (a 200000-byte trusted body must come through whole)"
    fi
  done
  (( ok )) && pass "M-BIG: a 200000-byte trusted body keeps its marker and its length in both views (the body never rides in argv)"
}
# rc2_stage <stage>: the last run_case_raw was rc 2 with EMPTY stdout, no stub miss, and stderr names that stage (two guards that both end in rc 2 stay distinguishable)
rc2_stage() { (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 2 && -z "$RAW_OUT" ]] && grep -q "stage '$1' failed" "$SB/err.log"; }
h_recfail() { # M-RECFAIL a failing record build is rc 2 with EMPTY stdout in both views, never a silently dropped comment; the twin (jq healthy) succeeds
  assert_fixture_dir "$SB"
  mkdir -p "$SB/bin-jqfail"; cp "$SB/bin/gh" "$SB/bin-jqfail/gh"
  printf '#!/usr/bin/env bash\ncase " $* " in *" -Rsc "*) exit 5 ;; esac\nexec %q "$@"\n' "$REAL_JQ" > "$SB/bin-jqfail/jq"; chmod +x "$SB/bin-jqfail/gh" "$SB/bin-jqfail/jq"
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  local view ok=1
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    STUB_BIN="$SB/bin-jqfail" run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 2 || -n "$RAW_OUT" ]]; then ok=0; fail "M-RECFAIL ($view): a failing record build must be rc 2 + empty stdout, got rc=$RAW_RC out=[$RAW_OUT]"; fi
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || -z "$RAW_OUT" ]]; then ok=0; fail "M-RECFAIL twin ($view): a healthy jq must succeed, got rc=$RAW_RC"; fi
  done
  mkdir -p "$SB/bin-jqempty"; cp "$SB/bin/gh" "$SB/bin-jqempty/gh"   # a record build that EXITS 0 and prints nothing: the empty-record arm
  printf '#!/usr/bin/env bash\ncase " $* " in *" -Rsc "*) exit 0 ;; esac\nexec %q "$@"\n' "$REAL_JQ" > "$SB/bin-jqempty/jq"; chmod +x "$SB/bin-jqempty/gh" "$SB/bin-jqempty/jq"
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    STUB_BIN="$SB/bin-jqempty" run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if ! rc2_stage record; then ok=0; fail "M-RECFAIL empty record ($view): an rc-0 record build with no output must be rc 2 + empty stdout naming stage record, got rc=$RAW_RC out=[$RAW_OUT]"; fi
  done
  (( ok )) && pass "M-RECFAIL: a failing record build, and one that exits 0 with no output, is rc 2 with no output in both views; the healthy-jq twin succeeds"
}
FSM_OK=1
fsm_case() { # <label> <body> <expected stripped body>   one trusted comment through the {t,b} view
  mkc "$SB/h.json" priv-op "$2" "$T2"; mkp 'priv-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  local got; got="$(bodies_of "$RAW_OUT")"
  if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || "$got" != "$3" ]]; then FSM_OK=0; fail "M-FENCE $1: rc=$RAW_RC want=[$3] got=[$got]"; fi
}
h_fsm() { # M-FENCE the strip is a fence state machine: opener/closer character and length, indentation, an unclosed fence
  FSM_OK=1; local M="S2-ACTIVATED: $T2"
  fsm_case "flat backtick fence" $'before\n```\n'"$M"$'\n```\nafter' $'before\nafter'
  fsm_case "tilde fence" $'before\n~~~\n'"$M"$'\n~~~\nafter' $'before\nafter'
  fsm_case "4-backtick outer around a 3-backtick line (the marker inside is NOT live)" $'````\n```\n'"$M"$'\n```\n````\nafter' 'after'
  fsm_case "a backtick fence is not closed by a tilde line" $'```\nin\n~~~\n'"$M"$'\n```\nafter' 'after'
  fsm_case "a tilde fence is not closed by a backtick line" $'~~~\nin\n```\n'"$M"$'\n~~~\nafter' 'after'
  fsm_case "a 4-space indented line is not a fence (the marker after it counts)" $'    ```\n'"$M"$'\nafter' $'    ```\n'"$M"$'\nafter'
  fsm_case "a 4-space indented line does not close an open fence" $'```\nM1\n    ```\nM2\n```\nafter' 'after'
  fsm_case "a longer closer closes" $'```\nM\n`````\nafter' 'after'
  fsm_case "a shorter closer does not close" $'````\nM\n```\nM2\n````\nafter' 'after'
  fsm_case "a closer with trailing text does not close" $'```\nM\n``` x\nM2\n```\nafter' 'after'
  fsm_case "a 3-space indented opener is a fence" $'   ```\nM\n   ```\nafter' 'after'
  fsm_case "an opener's info string is part of the opener" $'```bash\nM\n```\nafter' 'after'
  fsm_case "a marker after a properly closed fence counts" $'```\nx\n```\n'"$M" "$M"
  fsm_case "an unclosed fence strips to the end of the body" $'before\n```\n'"$M" 'before'
  fsm_case "a CRLF closer closes the fence (the marker after it counts)" $'```\r\nM\r\n```\r\n'"$M" "$M"
  fsm_case "a two-backtick line is not a fence" $'``\nM\n``\nafter' $'``\nM\n``\nafter'
  fsm_case "a two-tilde line is not a fence" $'~~\nM\n~~\nafter' $'~~\nM\n~~\nafter'
  fsm_case "a tab-indented backtick line is indented code, not a fence" $'\t```\nM\nafter' $'\t```\nM\nafter'
  fsm_case "a backtick opener whose info string holds a backtick is inline code, not a fence (the marker after it is KEPT)" $'```x``` inline code\n'"$M"$'\nafter' $'```x``` inline code\n'"$M"$'\nafter'
  fsm_case "a tilde opener may carry a backtick in its info string (still a fence)" $'~~~ a`b\nM\n~~~\nafter' 'after'
  fsm_case "a lone CR is a line ending: a fence opened after it strips the marker inside it" $'text\r```\n'"$M"$'\n```' 'text'
  fsm_case "several lone CRs in one body are each a line ending (a global substitution, not the first CR only)" $'a\rb\r```\n'"$M"$'\n```' $'a\nb'
  fsm_case "CRLF line endings are left alone" $'one\r\ntwo' $'one\r\ntwo'
  (( FSM_OK )) && pass "M-FENCE: 23 fence shapes (flat, tilde, 4-backtick wrapper, mixed characters, indentation, tab, closer length, CRLF closer, 2-char runs, trailing text, backtick info string, lone CR, unclosed) strip as CommonMark-style fences do; HTML comments and <pre> are not handled"
}
h_repo() { # M-REPO a non-default repository argument is used in BOTH the permission URL and the issue read, in BOTH views; the default repo is never touched
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  local view pos ok=1 got
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    REPO_EXP=other/repo run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv" other/repo
    if [[ "$view" == trusted_verdict_comments ]]; then got="$(bodies_of "$RAW_OUT")"; else got="$RAW_OUT"; fi
    pos=0; if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$got" == "S2-ACTIVATED: $T2" ]] && grep -qxF 'issue 9818' "$SB/req.log" && grep -qxF 'perm priv-op' "$SB/req.log"; then pos=1; fi
    REPO_EXP=other/repo run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( pos == 0 )) || (( RAW_MISS != 1 )); then ok=0; fail "M-REPO ($view): other/repo call ok=$pos; default-repo twin miss=$RAW_MISS (want 1)"; fi
  done
  (( ok )) && pass "M-REPO: in both views repo other/repo is used for the issue read AND the permission URL; a call without it asks the DEFAULT repo and the stub refuses it"
}
h_case() { # M-CASE logins are case-insensitive: Admin1 and admin1 are one user, one permission lookup, both comments kept
  mkc "$SB/h.json" Admin1 "one" "$T1" admin1 "two" "$T2"; mkp 'Admin1\tadmin\nadmin1\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$(nreq perm)" == 1 ]] && in_out one && in_out two; then
    pass "M-CASE: comments by Admin1 and admin1 cost ONE permission request and both are kept (the memo key is the lower-cased login)"
  else fail "M-CASE: rc=$RAW_RC miss=$RAW_MISS perm-requests=$(nreq perm) (want 1) out=[$RAW_OUT]"; fi
}
h_login_shape() { # M-SHAPE login boundaries: 39 chars resolve; 40, a trailing newline, %, ., a leading dash are refused with ZERO requests
  local l39 l40; l39="$(printf 'a%.0s' {1..39})"; l40="${l39}a"
  mkc "$SB/h.json" "$l39" ok39 "$T1" "$l40" evil40 "$T1" $'nl-op\n' evilnl "$T1" 'a%2fb' evilpct "$T1" 'a.b' evildot "$T1" '-lead' evildash "$T1"
  mkp "$l39\\tadmin\\n"   # ONLY the 39-char login has a permission row: a refused shape that reached the permission endpoint would also exit the stub non-zero
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$(nreq perm)" == 1 ]] && grep -qxF "perm $l39" "$SB/req.log" && in_out ok39 && ! bodies_of "$RAW_OUT" | grep -q evil; then
    pass "M-SHAPE: a 39-char login resolves; a 40-char login, a trailing newline, %, . and a leading dash are refused with zero requests"
  else fail "M-SHAPE: rc=$RAW_RC miss=$RAW_MISS perm-requests=$(nreq perm) (want 1) out-lines=$(bodies_of "$RAW_OUT" | grep -c .)"; fi
}
h_null_author() { # M-NULLAUTH a comment whose author is JSON null (a deleted account) is dropped, never fatal for the thread
  assert_fixture_dir "$SB"
  printf '%s\n' '{"comments":[{"author":null,"authorAssociation":"OWNER","body":"RESULT: PASS","createdAt":"'"$T1"'"},{"author":{"login":"priv-op"},"authorAssociation":"CONTRIBUTOR","body":"keep","createdAt":"'"$T2"'"}]}' > "$SB/h.json"
  mkp 'priv-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out keep && ! in_out 'RESULT: PASS' && [[ "$(nreq perm)" == 1 ]]; then
    pass "M-NULLAUTH: a comment with author null is dropped and the rest of the thread is read"
  else fail "M-NULLAUTH: rc=$RAW_RC miss=$RAW_MISS out=[$RAW_OUT]"; fi
}
h_underscore() { # must-PASS: an underscore is a legal login character and the login resolves
  mkc "$SB/h.json" a_b-op "S2-ACTIVATED: $T2" "$T2"; mkp 'a_b-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out "S2-ACTIVATED: $T2" && grep -qxF 'perm a_b-op' "$SB/req.log"; then
    pass "must-PASS: a login with an underscore resolves and its comment is kept"
  else fail "underscore login: rc=$RAW_RC miss=$RAW_MISS out=[$RAW_OUT]"; fi
}
h_inherit() { # M-INHERIT an EXPORTED scalar named like the memo must not become key 0: login 0 is looked up, not pre-trusted
  local ok=1 perm
  for perm in read admin; do
    mkc "$SB/h.json" 0 "S2-ACTIVATED: $T2" "$T2"; mkp "0\\t$perm\\n"
    XENV=(_TRUSTED_VERDICT_PERM=admin); run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"; XENV=()
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || "$(nreq perm)" != 1 ]]; then ok=0; fail "M-INHERIT (permission=$perm): rc=$RAW_RC requests=$(nreq perm) (want rc 0 and ONE request: login 0 must be looked up)"; fi
    if [[ "$perm" == read ]] && in_out "S2-ACTIVATED: $T2"; then ok=0; fail "M-INHERIT: login 0 with permission=read was trusted through an inherited exported scalar"; fi
    if [[ "$perm" == admin ]] && ! in_out "S2-ACTIVATED: $T2"; then ok=0; fail "M-INHERIT twin: login 0 with permission=admin must be kept"; fi
  done
  (( ok )) && pass "M-INHERIT: an exported _TRUSTED_VERDICT_PERM=admin does not pre-trust login 0 (one lookup; read dropped, admin kept)"
}
nul_fixture() { # <trusted-body-json-escape> : one trusted admin comment whose body is the given JSON string content, one untrusted comment with a NUL body
  assert_fixture_dir "$SB"
  printf '%s\n' '{"comments":[{"author":{"login":"ro-op"},"authorAssociation":"OWNER","body":"x\u0000y","createdAt":"'"$T1"'"},{"author":{"login":"priv-op"},"authorAssociation":"CONTRIBUTOR","body":"'"$1"'","createdAt":"'"$T2"'"}]}' > "$SB/h.json"
  mkp 'ro-op\tread\npriv-op\tadmin\n'
}
h_nul() { # M-NUL a NUL byte in a TRUSTED body is rc 2 (bash would drop it and JOIN S2-ACTI<NUL>VATED into a live marker); in an untrusted body it is ignored
  local view ok=1
  nul_fixture 'S2-ACTI\u0000VATED: 2026-10-11T09:48:17Z'
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if ! rc2_stage nul; then ok=0; fail "M-NUL ($view): a NUL in a trusted body must be rc 2 + empty stdout naming stage nul, got rc=$RAW_RC out=[$RAW_OUT]"; fi
    if ! grep -q 'will not clear on retry' "$SB/err.log" || grep -q 'TRANSIENT' "$SB/err.log"; then ok=0; fail "M-NUL ($view): the NUL stage must say it is deterministic (will not clear on retry), never TRANSIENT, got err=[$(head -c 200 "$SB/err.log")]"; fi
  done
  nul_fixture 'S2-ACTIVATED: 2026-10-11T09:48:17Z'
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 ]] || ! grep -qF "S2-ACTIVATED: $T2" <<<"$RAW_OUT"; then ok=0; fail "M-NUL twin ($view): the same comment without a NUL, and an untrusted NUL body beside it, must succeed, got rc=$RAW_RC out=[$RAW_OUT]"; fi
  done
  (( ok )) && pass "M-NUL (synthetic: the fake gh runs the system jq; real gh rewrites U+0000 to ^@): a NUL in a trusted body is rc 2 with empty stdout (stage nul, deterministic wording) in both views; an untrusted NUL body and a NUL-free twin are fine"
}
mkfailtool() { # <dir> <tool> <script body>: a dir with the gh stub and ONE tool that fails in a chosen way
  assert_fixture_dir "$SB"; mkdir -p "$1"; cp "$SB/bin/gh" "$1/gh"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/$2"; chmod +x "$1/gh" "$1/$2"
}
h_stagefail() { # M-STAGE each post-trust stage that fails is rc 2 + empty stdout + a message naming THAT stage, in both views; the healthy twin succeeds
  local ok=1 view spec stage tool body
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  local -a specs=(
    "strip|awk|case \" \$* \" in *\" -F\"*) exec $REAL_AWK \"\$@\" ;; esac; exit 2"
    "decode|base64|exit 5"
    "author|jq|case \"\$*\" in *\".[0]\"*) exit 5 ;; esac; exec $REAL_JQ \"\$@\""
    "body|jq|case \"\$*\" in *\".[1]\"*) exit 5 ;; esac; exec $REAL_JQ \"\$@\""
    "created|jq|case \"\$*\" in *\".[2]\"*) exit 5 ;; esac; exec $REAL_JQ \"\$@\""
    "nulcheck|jq|case \"\$*\" in *\".[1:]\"*) exit 5 ;; esac; exec $REAL_JQ \"\$@\"")
  for spec in "${specs[@]}"; do
    stage="${spec%%|*}"; tool="${spec#*|}"; body="${tool#*|}"; tool="${tool%%|*}"
    mkfailtool "$SB/bin-fail-$stage" "$tool" "$body"
    for view in trusted_verdict_comments trusted_verdict_bodies; do
      STUB_BIN="$SB/bin-fail-$stage" run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
      if ! rc2_stage "$stage"; then ok=0; fail "M-STAGE ($view, $stage): a failing $tool must be rc 2 + empty stdout naming stage $stage, got rc=$RAW_RC out=[$RAW_OUT] err=[$(head -c 200 "$SB/err.log")]"; fi
    done
  done
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || -z "$RAW_OUT" ]]; then ok=0; fail "M-STAGE twin ($view): healthy tools must succeed, got rc=$RAW_RC"; fi
  done
  (( ok )) && pass "M-STAGE: a failing awk strip, base64 decode, and jq field extraction .[0] / .[1] / .[2] / the NUL probe each yield rc 2, empty stdout and a message naming that stage, in both views"
}
h_rowcount() { # M-ROWCOUNT a row-split loop that loses lines (a here-string failure, injected as a failing `read` after the first line) is rc 2, never a shorter thread
  local view ok=1
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T1" "$T1" priv-op "two" "$T1" priv-op "S2-DEACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    INJECT='_rn=0; read() { (( ++_rn > 1 )) && return 1; builtin read "$@"; }' run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if ! rc2_stage rowcount; then ok=0; fail "M-ROWCOUNT ($view): a read that fails after row 1 of 3 must be rc 2 + empty stdout naming stage rowcount, got rc=$RAW_RC out=[$RAW_OUT]"; fi
    run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || "$(grep -c . <<<"$RAW_OUT")" -lt 3 ]]; then ok=0; fail "M-ROWCOUNT twin ($view): the healthy read must return all 3 comments, got rc=$RAW_RC"; fi
  done
  (( ok )) && pass "M-ROWCOUNT: rows collected != rows in the input is rc 2 with empty stdout (stage rowcount), in both views; the healthy twin returns all three"
}
h_logincount() { # M-LOGINCOUNT a resolver that claims success but leaves nothing in the memo is rc 2 naming stage logincount (conservation of distinct logins)
  local view ok=1
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    INJECT='_trusted_verdict_permission() { return 0; }' run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if ! rc2_stage logincount; then ok=0; fail "M-LOGINCOUNT ($view): a resolver that memoizes nothing must be rc 2 + empty stdout naming stage logincount, got rc=$RAW_RC out=[$RAW_OUT] err=[$(head -c 200 "$SB/err.log")]"; fi
  done
  (( ok )) && pass "M-LOGINCOUNT: distinct logins resolved != distinct logins collected is rc 2 with empty stdout (stage logincount), in both views"
}
h_empty() { # M-EMPTY an empty thread, and a thread whose every comment is dropped (null author, bad login shape), is rc 0 with EMPTY stdout in both views: an empty read must never reach the row-split loop
  local view variant ok=1
  mkp 'priv-op\tadmin\n'
  for variant in empty alldropped; do
    assert_fixture_dir "$SB"
    if [[ "$variant" == empty ]]; then printf '%s\n' '{"comments":[]}' > "$SB/h.json"
    else printf '%s\n' '{"comments":[{"author":null,"authorAssociation":"OWNER","body":"RESULT: PASS","createdAt":"'"$T1"'"},{"author":{"login":"a/../b"},"authorAssociation":"OWNER","body":"RESULT: PASS","createdAt":"'"$T2"'"}]}' > "$SB/h.json"; fi
    for view in trusted_verdict_comments trusted_verdict_bodies; do
      run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
      if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 ]] || [[ -s "$SB/raw.out" ]] || [[ "$(nreq perm)" != 0 ]]; then ok=0; fail "M-EMPTY ($variant, $view): want rc 0, empty stdout and no permission request, got rc=$RAW_RC out=[$RAW_OUT] perm-requests=$(nreq perm)"; fi
    done
  done
  (( ok )) && pass "M-EMPTY: an empty thread and a thread with every comment dropped are rc 0 with empty stdout and zero permission requests, in both views"
}
h_bodyproj() { # M-BODYPROJ the bodies view's `jq -r .b` projection dying after printing its first record is rc 2 with EMPTY stdout (no prefix); the healthy twin returns both bodies
  assert_fixture_dir "$SB"
  mkfailtool "$SB/bin-bodyproj" jq "case \"\$*\" in \"-r .b\") $REAL_JQ \"\$@\" | head -n 1; exit 5 ;; esac; exec $REAL_JQ \"\$@\""
  mkc "$SB/h.json" priv-op "first" "$T1" priv-op "second" "$T2"; mkp 'priv-op\tadmin\n'
  local ok=1
  STUB_BIN="$SB/bin-bodyproj" run_case_raw trusted_verdict_bodies 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 2 ]] || [[ -s "$SB/raw.out" ]]; then ok=0; fail "M-BODYPROJ: a projection that prints a record and then fails must be rc 2 with EMPTY stdout, got rc=$RAW_RC out=[$RAW_OUT]"; fi
  run_case_raw trusted_verdict_bodies 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS != 0 )) || [[ "$RAW_RC" != 0 || "$RAW_OUT" != $'first\nsecond' ]]; then ok=0; fail "M-BODYPROJ twin: a healthy jq must return both bodies, got rc=$RAW_RC out=[$RAW_OUT]"; fi
  (( ok )) && pass "M-BODYPROJ: a bodies projection that dies half way is rc 2 with empty stdout (no prefix), so rc 2 always leaves stdout empty; the healthy twin returns both bodies"
}
h_rowextra() { # M-ROWEXTRA the conservation check is two-sided: a split loop that GAINS a row (an injected duplicate) is rc 2 naming stage rowcount, never a longer thread
  local view ok=1
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T1" "$T1" priv-op "two" "$T1" priv-op "S2-DEACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  for view in trusted_verdict_comments trusted_verdict_bodies; do
    INJECT='_rn=0; _prev=; read() { if (( ++_rn == 2 )); then b64="$_prev"; return 0; fi; builtin read "$@"; _rc=$?; _prev="$b64"; return $_rc; }' run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
    if ! rc2_stage rowcount; then ok=0; fail "M-ROWEXTRA ($view): a split that gains a duplicate row (4 rows for 3 comments) must be rc 2 + empty stdout naming stage rowcount, got rc=$RAW_RC out=[$RAW_OUT] err=[$(head -c 200 "$SB/err.log")]"; fi
  done
  (( ok )) && pass "M-ROWEXTRA: rows collected > rows in the input is rc 2 with empty stdout (stage rowcount), in both views: the count check is two-sided"
}
h_stageempty() { # M-STAGEEMPTY a decode or an author extraction that EXITS 0 and prints nothing is rc 2 naming THAT stage (not the next one), in both views
  local ok=1 view spec stage tool body
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  local -a specs=(
    "decode|base64|exit 0"
    "author|jq|case \"\$*\" in *\".[0]\"*) exit 0 ;; esac; exec $REAL_JQ \"\$@\"")
  for spec in "${specs[@]}"; do
    stage="${spec%%|*}"; tool="${spec#*|}"; body="${tool#*|}"; tool="${tool%%|*}"
    mkfailtool "$SB/bin-empty-$stage" "$tool" "$body"
    for view in trusted_verdict_comments trusted_verdict_bodies; do
      STUB_BIN="$SB/bin-empty-$stage" run_case_raw "$view" 9818 "$SB/h.json" "$SB/pm.tsv"
      if ! rc2_stage "$stage"; then ok=0; fail "M-STAGEEMPTY ($view, $stage): a $tool that exits 0 with no output must be rc 2 + empty stdout naming stage $stage, got rc=$RAW_RC out=[$RAW_OUT] err=[$(head -c 200 "$SB/err.log")]"; fi
    done
  done
  (( ok )) && pass "M-STAGEEMPTY: a base64 decode or a jq author extraction that exits 0 with no output is rc 2 naming that stage, in both views"
}
h_readonly() { # M-READONLY a readonly memo name is refused with a TRUTHFUL message (it is not a bash-3.2 shell); the unset twin sources cleanly
  assert_fixture_dir "$SB"
  local out rc twin trc ok=1
  out="$(env bash -c 'readonly _TRUSTED_VERDICT_PERM=x; source "$1"; echo "sourced-rc=$?"' _ "${LIB_UNDER:-$LIB}" 2>&1)"
  if [[ "$out" != *"sourced-rc=2"* || "$out" != *"readonly"* || "$out" == *"no associative arrays"* ]]; then ok=0; fail "M-READONLY: a readonly memo name must be refused (rc 2) naming 'readonly', never the no-associative-arrays text, got [$out]"; fi
  twin="$(env bash -c 'source "$1"; echo "sourced-rc=$?"' _ "${LIB_UNDER:-$LIB}" 2>&1)"
  if [[ "$twin" != "sourced-rc=0" ]]; then ok=0; fail "M-READONLY twin: the same source without a readonly name must be silent and rc 0, got [$twin]"; fi
  (( ok )) && pass "M-READONLY: a readonly _TRUSTED_VERDICT_PERM is refused (rc 2) with a message that says readonly, not 'no associative arrays'; the clean twin sources silently"
}
LIB_ROWS=(h_h1 h_h2 h_h3 h_h4_parity h_h4_abs h_h5 h_h6 h_h7 h_h8 h_noslice h_h10 h_crlf h_h11 h_big h_recfail h_fsm h_repo h_case h_login_shape h_null_author h_underscore h_inherit h_nul h_stagefail h_rowcount h_logincount h_empty h_bodyproj h_rowextra h_stageempty h_readonly)
for _r in "${LIB_ROWS[@]}"; do "$_r"; done

# --- harness integrity: a stub that answers `admin` to EVERYONE must redden the negative rows (the rows can fail) ----------
assert_fixture_dir "$SB"
mkdir -p "$SB/bin-admin"
sed 's|^    perm="$(awk .*$|    perm=admin|' "$SB/bin/gh" > "$SB/bin-admin/gh"; chmod +x "$SB/bin-admin/gh"
if cmp -s "$SB/bin/gh" "$SB/bin-admin/gh"; then fail "harness: the always-admin stub copy is identical to the real stub (the edit did not land)"
else
  _p0=$PASS; _f0=$FAIL
  STUB_BIN="$SB/bin-admin"; for _r in h_h2 h_h3 h_h7; do "$_r" >/dev/null; done; unset STUB_BIN
  _reds=$((FAIL - _f0)); PASS=$_p0; FAIL=$_f0
  if (( _reds >= 3 )); then pass "harness: an always-admin permission stub turns the negative rows M-H2, M-H3 and M-H7 red ($_reds reds)"
  else fail "harness: an always-admin stub turned only $_reds row(s) red (want >= 3)"; fi
fi

# --- lib mutants: each mutated COPY of the lib must redden at least one NAMED row ------------------------------------------
MUT_RUN=0; MUT_CAUGHT=0
MUT_LANDED=1; MUT_CRASHED=0; MUT_REDS=0; MUT_FILE=""
# mutant_lib_build <name> <old1> <new1> [<old2> <new2> ...]   every anchor must occur exactly once; sets MUT_LANDED and MUT_FILE
mutant_lib_build() {
  local name="$1"; shift
  MUT_FILE="$SB/mut-$name.sh"; MUT_LANDED=1
  if ! python3 - "$LIB" "$MUT_FILE" "$@" <<'PY'
import sys
src, dst = sys.argv[1:3]
pairs = sys.argv[3:]
s = open(src).read()
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    if s.count(old) != 1:
        sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
    s = s.replace(old, new)
open(dst, "w").write(s)
PY
  then MUT_LANDED=0; return 0; fi
  cmp -s "$MUT_FILE" "$LIB" && MUT_LANDED=0
  return 0
}
# lib_rows_quiet <lib file> <rows...>   runs the rows against that lib, counting reds without recording them as this suite's failures.
# Sets MUT_REDS and MUT_CRASHED (a file that does not parse, or a bash-level error in any row's stderr, means every red proves nothing)
lib_rows_quiet() {
  local lf="$1" r p0 f0; shift
  MUT_REDS=0; MUT_CRASHED=0; rm -f "$SB/crashed"
  bash -n "$lf" 2>/dev/null || MUT_CRASHED=1
  LIB_UNDER="$lf"
  for r in "$@"; do p0=$PASS; f0=$FAIL; "$r" >/dev/null; MUT_REDS=$((MUT_REDS + FAIL - f0)); PASS=$p0; FAIL=$f0; done
  LIB_UNDER=""
  [[ -f "$SB/crashed" ]] && MUT_CRASHED=1
  return 0
}
mutant_lib() { # <name> <rows, space separated> <old1> <new1> [<old2> <new2> ...]
  local name="$1" rows="$2"; shift 2
  MUT_RUN=$((MUT_RUN + 1))
  mutant_lib_build "$name" "$@"
  if (( MUT_LANDED == 0 )); then fail "MUTANT $name: mutation did NOT land (or is byte-identical to the lib)"; return; fi
  # shellcheck disable=SC2086
  lib_rows_quiet "$MUT_FILE" $rows
  if (( MUT_CRASHED )); then fail "MUTANT $name: the mutant CRASHED (a bash error), which proves nothing"; return; fi
  if (( MUT_REDS > 0 )); then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "MUTANT $name turned $MUT_REDS assertion(s) red"
  else fail "MUTANT $name SURVIVED: none of [$rows] went red"; fi
}
Q="'"
PRED='    admin|maintain|write) return 0 ;;'
mutant_lib m-triage-trusted  "h_h3" "$PRED" '    admin|maintain|write|triage) return 0 ;;'
mutant_lib m-no-maintain     "h_h3" "$PRED" '    admin|write) return 0 ;;'
mutant_lib m-no-write        "h_h3" "$PRED" '    admin|maintain) return 0 ;;'
mutant_lib m-pred-always     "h_h2 h_h3 h_h7" "$PRED" '    *) return 0 ;;'
SEL='        | select((.author.login // "") != "")'
mutant_lib m-assoc-prefilter "h_h1" "$SEL" "$SEL"$'\n''        | select(.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR"))'
FENCE_CALL='| _trusted_verdict_strip_fences)"'
mutant_lib m-strip-empty     "h_h4_abs h_fsm" "$FENCE_CALL" '| cat)"'
mutant_lib m-naive-toggle    "h_fsm h_h4_abs" "$FENCE_CALL" "| awk '/^[[:space:]]*(\`\`\`|~~~)/ { f = !f; next } !f { print }')\""
RESOLVE='    if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then'
mutant_lib m-resolver-subshell "h_h1 h_h8" "$RESOLVE" '    if ! _mut="$(_trusted_verdict_permission "$login" "$repo")"; then'
mutant_lib m-partial-output  "h_h6" "$RESOLVE"$'\n      return 2' "$RESOLVE"$'\n      continue' \
  '_trusted_verdict_stage_fail logincount "$issue"; return 2;' 'true;' \
  "    out=\"\${out}\${rec}\"\$${Q}\\n${Q}" \
  "    printf '%s\\n' \"\$body\"; out=\"\${out}\${rec}\"\$${Q}\\n${Q}"
# EQUIVALENT single edits (measured: each survives every row above, so neither is a mutant on its own): turning the memo guard off alone, or the `seen` array (pass 1's distinct-author
# collector) off alone, each leave exactly one request per distinct author because the OTHER one still deduplicates. Only the two together are a mutant.
mutant_lib m-no-dedupe       "h_h8" '  if [[ -n "${_TRUSTED_VERDICT_PERM[$key]:-}" ]]; then' '  if false; then' \
  '    if [[ -z "${seen[${author,,}]+x}" ]]; then' '    if true; then'
mutant_lib m-jq-slice-100     "h_noslice" '        .comments[]' '        .comments[0:100][]'
mutant_lib m-t-empty         "h_h5" "${Q}{t: \$t, b: .}${Q}" "${Q}{t: \"\", b: .}${Q}"
CREATED_LINE='    created="$(printf '"'"'%s'"'"' "${rows[i]}" | jq -r '"'"'.[2]'"'"')" || { _trusted_verdict_stage_fail created "$issue"; return 2; }'
mutant_lib m-validate-in-core "h_h5" "$CREATED_LINE" "$CREATED_LINE"'
    [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 2'
mutant_lib m-second-read     "h_h10" '  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  if ! printf' '  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  gh issue view "$issue" --repo "$repo" --json comments --jq ".comments[].body" >/dev/null 2>&1
  [[ -n "$records" ]] || return 0
  if ! printf'
mutant_lib m-no-jq-flag      "h_h1" "                 --jq '.permission // empty' 2>\"\$errf\")\"; then" '                 2>"$errf")"; then'
mutant_lib m-no-shape-guard  "h_h11" '        | select(.author.login | test("\\A[A-Za-z0-9][A-Za-z0-9_-]{0,38}\\z"))
' ''
REC='    if ! rec="$(printf '"'"'%s'"'"' "$body" | jq -Rsc --arg t "$created" '"'"'{t: $t, b: .}'"'"')" || [[ -z "$rec" ]]; then'
mutant_lib m-argv-body       "h_big" "$REC" '    rec="$(jq -nc --arg t "$created" --arg b "$body" '"'"'{t: $t, b: $b}'"'"')"; if false; then'
mutant_lib m-rec-unchecked   "h_recfail" "$REC" '    rec="$(printf '"'"'%s'"'"' "$body" | jq -Rsc --arg t "$created" '"'"'{t: $t, b: .}'"'"')"; if false; then'
mutant_lib m-memo-key-raw    "h_case" '  key="${login,,}"' '  key="$login"'
mutant_lib m-read-key-raw    "h_case" '${_TRUSTED_VERDICT_PERM[${author,,}]:-}' '${_TRUSTED_VERDICT_PERM[$author]:-}'
mutant_lib m-repo-url        "h_repo" 'gh api "repos/${repo}/collaborators/${login}/permission"' 'gh api "repos/jikig-ai/soleur/collaborators/${login}/permission"'
mutant_lib m-repo-view       "h_repo" 'gh issue view "$issue" --repo "$repo" --json comments' 'gh issue view "$issue" --repo "jikig-ai/soleur" --json comments'
mutant_lib m-shape-len       "h_login_shape" '{0,38}\\z' '{0,39}\\z'
mutant_lib m-shape-nl        "h_login_shape" '{0,38}\\z' '{0,38}$'
mutant_lib m-shape-chars     "h_login_shape" '[A-Za-z0-9_-]{0,38}' '[A-Za-z0-9_.%-]{0,38}'
mutant_lib m-shape-dash      "h_login_shape" '\\A[A-Za-z0-9][A-Za-z0-9_-]' '\\A[A-Za-z0-9-][A-Za-z0-9_-]'
mutant_lib m-no-author-select "h_null_author" "$SEL"$'\n' ''
mutant_lib m-rec-empty-arm   "h_recfail" ' || [[ -z "$rec" ]]; then' '; then'
BODIES_CALL='  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  # captured'
mutant_lib m-bodies-repo     "h_repo" "$BODIES_CALL" '  records="$(_trusted_verdict_core "$issue" "jikig-ai/soleur")" || return 2
  [[ -n "$records" ]] || return 0
  # captured'
COMMENTS_CALL='  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  if ! printf'
mutant_lib m-comments-repo   "h_repo" "$COMMENTS_CALL" '  records="$(_trusted_verdict_core "$issue" "jikig-ai/soleur")" || return 2
  [[ -n "$records" ]] || return 0
  if ! printf'
mutant_lib m-shape-no-underscore "h_underscore" '[A-Za-z0-9_-]{0,38}' '[A-Za-z0-9-]{0,38}'
mutant_lib m-inherit-unset   "h_inherit" 'unset _TRUSTED_VERDICT_PERM 2>/dev/null' ':'
mutant_lib m-no-nul          "h_nul" '_trusted_verdict_stage_fail nul "$issue" "A trusted comment contains a NUL byte; this will not clear on retry: edit that comment."; return 2 ;; esac' ';; esac'
mutant_lib m-no-lonecr       "h_fsm" 'if contains("\r") then gsub("\r(?!\n)"; "\n") else . end' '.'
mutant_lib m-lonecr-once     "h_fsm" 'then gsub("\r(?!\n)"; "\n") else' 'then sub("\r(?!\n)"; "\n") else'
mutant_lib m-rowcount-lt     "h_rowextra" '(( ${#rows[@]} != n_in ))' '(( ${#rows[@]} < n_in ))'
mutant_lib m-no-raw-guard    "h_empty" '  if [[ -n "$raw" ]]; then
    while IFS= read -r b64; do' '  if true; then
    while IFS= read -r b64; do'
mutant_lib m-bodies-proj-unchecked "h_bodyproj" 'printf x)" || return 2' 'printf x)" || true'
mutant_lib m-decode-nonempty "h_stageempty" ' && [[ -n "$row" ]]' ''
mutant_lib m-author-nonempty "h_stageempty" ' && [[ -n "$author" ]]' ''
mutant_lib m-unset-unchecked "h_readonly" 'if ! unset _TRUSTED_VERDICT_PERM 2>/dev/null; then' 'unset _TRUSTED_VERDICT_PERM 2>/dev/null; if false; then'
mutant_lib m-nul-wording     "h_nul" ' "A trusted comment contains a NUL byte; this will not clear on retry: edit that comment."' ''
mutant_lib m-no-rowcount     "h_rowcount" '_trusted_verdict_stage_fail rowcount "$issue"; return 2;' 'true;'
mutant_lib m-no-logincount   "h_logincount" '_trusted_verdict_stage_fail logincount "$issue"; return 2;' 'true;'
for _st in strip decode author body created nulcheck; do
  mutant_lib "m-stage-$_st-unchecked" "h_stagefail" "_trusted_verdict_stage_fail $_st \"\$issue\"; return 2;" 'true;'
done
INFO_LINE='      if (ch == "`" && index(rest, "`") > 0) n = 0'
mutant_lib m-fsm-no-info     "h_fsm" "$INFO_LINE"$'\n' ''
mutant_lib m-fsm-info-tilde  "h_fsm" "$INFO_LINE" '      if (index(rest, "`") > 0) n = 0'
mutant_lib m-fsm-crcloser    "h_fsm" 'rest ~ /^[ \t\r]*$/' 'rest ~ /^[ \t]*$/'
mutant_lib m-fsm-2tick       "h_fsm" 'match(t, /^```+/)' 'match(t, /^``+/)'
mutant_lib m-fsm-2tilde      "h_fsm" 'match(t, /^~~~+/)' 'match(t, /^~~+/)'
mutant_lib m-fsm-tab         "h_fsm" 'match(line, /^ */)' 'match(line, /^[ \t]*/)'

# --- harness controls: the mutant helper must be able to report a SURVIVOR, a CRASH, and a clean IDENTITY, or its verdicts mean nothing ----------
CTRL_OK=0
mutant_lib_build c-equivalent "$PRED" '    admin|maintain|write) return 0; ;;'
lib_rows_quiet "$MUT_FILE" h_h2 h_h3 h_h7
if (( MUT_LANDED == 1 && MUT_CRASHED == 0 && MUT_REDS == 0 )); then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an equivalent mutant survives (landed, no crash, no row red)"
else fail "harness control: the equivalent mutant was not reported as a survivor (landed=$MUT_LANDED crashed=$MUT_CRASHED reds=$MUT_REDS)"; fi
mutant_lib_build c-crash-parse "$PRED" "$PRED"$'\n  readonly X=('
lib_rows_quiet "$MUT_FILE" h_h2 h_h3
if (( MUT_LANDED == 1 && MUT_CRASHED == 1 )); then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that does not parse is flagged as crashed"
else fail "harness control: the unparsable mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
mutant_lib_build c-crash-runtime "$PRED" '    admin|maintain|write) no_such_command_zz; return 0 ;;'
lib_rows_quiet "$MUT_FILE" h_h2 h_h3
if (( MUT_LANDED == 1 && MUT_CRASHED == 1 )) && bash -n "$MUT_FILE" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that parses but fails at runtime is flagged as crashed"
else fail "harness control: the runtime-crashing mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
mutant_lib_build c-crash-unbound "$PRED" '    admin|maintain|write) : "$UNSET_ZZ_SENTINEL"; return 0 ;;'
lib_rows_quiet "$MUT_FILE" h_h2 h_h3
if (( MUT_LANDED == 1 && MUT_CRASHED == 1 )) && bash -n "$MUT_FILE" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that dies on an unbound variable is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the unbound-variable mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
assert_fixture_dir "$SB"
cp "$LIB" "$SB/identity.sh"
lib_rows_quiet "$SB/identity.sh" "${LIB_ROWS[@]}"
if (( MUT_REDS == 0 && MUT_CRASHED == 0 )); then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an unmutated copy of the lib turns no row red over the full row set"
else fail "harness control: the identity copy turned $MUT_REDS row(s) red (crashed=$MUT_CRASHED): the harness is polluted"; fi
# the verdict itself: an inert, a PARSE-crashing and an anchor-NOT-LANDED mutant fed through mutant_lib must each be REPORTED as what it is
# (exactly one failure, nothing counted as caught, the right word in the report); counters are restored after. ctrl_verdict refuses an empty
# word, and the last control below asserts it can REFUSE (a wrong word must fail it), so deleting the word check from the helper goes red.
ctrl_verdict() { # <name> <word the report must contain> <rows> <old> <new>
  local name="$1" word="$2"; shift 2
  [[ -n "$word" ]] || return 2
  local p0=$PASS f0=$FAIL r0=$MUT_RUN c0=$MUT_CAUGHT nfail ncaught
  assert_fixture_dir "$SB"
  mutant_lib "$name" "$@" >"$SB/ctrl-$name.out"
  nfail=$((FAIL - f0)); ncaught=$((MUT_CAUGHT - c0))
  PASS=$p0; FAIL=$f0; MUT_RUN=$r0; MUT_CAUGHT=$c0
  (( nfail == 1 && ncaught == 0 )) && grep -q -- "$word" "$SB/ctrl-$name.out"
}
if ctrl_verdict c-inert SURVIVED "h_h2 h_h3" "$PRED" '    admin|maintain|write) return 0; ;;'; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an inert mutant is reported SURVIVED and makes the suite red"
else fail "harness control: an inert mutant was not reported as a survivor"; fi
if ctrl_verdict c-parse-verdict CRASHED "h_h2 h_h3" "$PRED" "$PRED"$'\n  readonly X=('; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a PARSE-crashing mutant fed through mutant_lib is reported CRASHED and makes the suite red"
else fail "harness control: a parse-crashing mutant was not reported as CRASHED through mutant_lib"; fi
if ctrl_verdict c-nolanding 'did NOT land' "h_h2 h_h3" 'ANCHOR_THAT_IS_NOT_IN_THE_LIB_ZZ' 'x'; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant whose anchor does not land is reported NOT LANDED and makes the suite red"
else fail "harness control: a mutant with a missing anchor was not reported as NOT LANDED"; fi
if ! ctrl_verdict c-wrongword CRASHED "h_h2 h_h3" "$PRED" '    admin|maintain|write) return 0; ;;' && ! ctrl_verdict c-emptyword '' "h_h2 h_h3" "$PRED" '    admin|maintain|write) return 0; ;;'; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: the verdict helper REFUSES a report that lacks the expected word (and an empty word), so its word check cannot be deleted green"
else fail "harness control: the verdict helper accepted a report without the expected word"; fi
# CRASH_RE alternatives: one runtime-only mutant per alternative (each parses; only that alternative can flag it)
mutant_lib_build c-crash-badsub "$PRED" '    admin|maintain|write) _x=a; : "${_x@Z}"; return 0 ;;'
lib_rows_quiet "$MUT_FILE" h_h2 h_h3
if (( MUT_LANDED == 1 && MUT_CRASHED == 1 )) && bash -n "$MUT_FILE" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that dies on a bad substitution is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the bad-substitution mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
mutant_lib_build c-crash-syntax "$PRED" "    admin|maintain|write) eval '('; return 0 ;;"
lib_rows_quiet "$MUT_FILE" h_h2 h_h3
if (( MUT_LANDED == 1 && MUT_CRASHED == 1 )) && bash -n "$MUT_FILE" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant whose runtime eval dies on a syntax error is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the runtime syntax-error mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
if (( CTRL_OK != 11 )); then fail "harness controls: $CTRL_OK of 11 held"; fi
if (( MUT_RUN == MUT_CAUGHT && MUT_RUN >= 56 )); then pass "LIB MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "LIB MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 56)"; fi

echo ""
echo "passed=$PASS failed=$FAIL"

# ANTI-VACUITY FLOOR. Reported with printf + exit, never through pass()/fail() —
# those are the helpers this backstops.
#
# TWO properties are load-bearing here, and only one of them is obvious.
#
# 1. SELFTEST_PASSES is re-bound HERE as a literal rather than reused from the
#    self-test ~200 lines above. scripts/guard-vacuity-floor.test.sh proves a
#    floor FIRES by slicing the `if` plus its CONTIGUOUS simple assignments into
#    a mutant with every counter zeroed; a subtrahend bound far away is unbound
#    in that slice and the mutant dies at `set -u` before reaching the floor.
#    The literal is proven by the self-test, which asserts PASS==1 at that point.
#
# 2. The MESSAGE must carry a word from that guard's FIRES sentinel vocabulary
#    (`anti-vacuity`, `assertion floor`, `only <n>`, `[FATAL]`, `vacuit`, …).
#    This is the one that actually bit: the first version of this floor read
#    `FLOOR: executed %d real assertions`, which satisfies property 1 perfectly
#    and matches NO sentinel — so the guard saw a non-zero exit with no
#    recognised output, fell through to its shell-error branch, and scored the
#    floor CONSTRUCTION (status unknown) rather than FIRES. The repo-wide ratchet
#    grew 15 -> 16 and named this file. Measured both ways before fixing: the
#    hand-built mutant exited 1 correctly the whole time, which is exactly why
#    reading the slice was the wrong place to look. A floor whose message the
#    meta-guard cannot recognise is indistinguishable from a floor that crashed.
SELFTEST_PASSES=1
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=112
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
