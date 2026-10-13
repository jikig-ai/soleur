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
# a bash-level error in the lib under test (a mutant that CRASHES reddens every row, which proves nothing about the guard it removed)
CRASH_RE='syntax error|command not found|unbound variable|bad substitution|unexpected EOF'
note_crash() { if grep -qE "$CRASH_RE" "$SB/err.log" 2>/dev/null; then : > "$SB/crashed"; fi; }
stub_env() { # <issue> <comments-json-file> <perms-file>   (resets the request and refusal logs)
  : > "$SB/req.log"; : > "$SB/refused.log"
  STUB_ENV=(PATH="${STUB_BIN:-$SB/bin}:$PATH" STUB_COMMENTS="$2" STUB_PERMS="$3" STUB_EXPECT_ISSUE="$1" STUB_EXPECT_REPO="${REPO_EXP:-jikig-ai/soleur}"
            STUB_LOG="$SB/req.log" STUB_REFUSED="$SB/refused.log")
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
# Loop 1 resolves exactly the author set loop 2 reads, so a memo MISS is unreachable
# in the shipped lib. That is why it needs a mutation rather than a fixture: the
# original code said `*) continue ;;`, which merges "resolved as untrusted" with
# "never resolved at all" — the collapse this lib's own header forbids, at the one
# place the header did not assert it. Neuter loop 1's resolver call and require the
# lib to REFUSE rather than quietly return a shorter list.
MUT="$SB/trusted-verdict-no-resolve.sh"
sed 's|^    if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then|    if false; then|' "$LIB" > "$MUT"
if diff -q "$LIB" "$MUT" >/dev/null; then
  fail "row 9: the resolver-call marker is absent from the lib — the mutation did not land and this row is vacuous"
else
  cat > "$SB/one-verdict.json" <<'JSON'
{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}
JSON
  printf 'deruelle\tadmin\n' > "$SB/perms-mut"
  stub_env 5733 "$SB/one-verdict.json" "$SB/perms-mut"
  mout="$(
    env "${STUB_ENV[@]}" bash -c 'set -uo pipefail; source "$1"; trusted_verdict_bodies "$2" >/dev/null 2>&1; echo $?' _ "$MUT" 5733
  )"
  if [[ "$mout" == "2" ]]; then
    pass "row 9 MUTATION: an author with no memoized permission yields TRANSIENT (rc=2), not a silent drop"
  else
    fail "row 9 MUTATION: expected rc=2 from the un-resolved author; got rc=$mout"
  fi
fi

# =====================================================================================
# THE TWO-VIEW MATRIX (rows M-H1 .. M-H11). Each row is a FUNCTION so a lib mutant (below) can
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
  printf '{"comments":[%s]}\n' "$(IFS=,; printf '%s' "${a[*]}")" > "$f"
}
mkp() { printf "$1" > "$SB/pm.tsv"; }   # printf format with literal \t and \n
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
h_h9() { # M-H9 more than 100 comments are all returned (the DEACTIVATED marker past the first 100 is read)
  local i body c=()
  for ((i = 1; i <= 150; i++)); do body="n$i"; (( i == 130 )) && body="S2-DEACTIVATED: $T2"; c+=(many-op "$body" "$T1"); done
  mkc "$SB/h.json" "${c[@]}"; mkp 'many-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && [[ "$(wc -l <<<"$RAW_OUT")" -eq 150 ]] && in_out "S2-DEACTIVATED: $T2"; then
    pass "M-H9: 150 comments through the GraphQL shape are all returned, the marker at position 130 included"
  else fail "M-H9: rc=$RAW_RC lines=$(wc -l <<<"$RAW_OUT")"; fi
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
h_recfail() { # M-RECFAIL a failing record build is rc 2 with EMPTY stdout in both views, never a silently dropped comment; the twin (jq healthy) succeeds
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
  (( ok )) && pass "M-RECFAIL: a failing record build is rc 2 with no output in both views; the healthy-jq twin succeeds"
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
  (( FSM_OK )) && pass "M-FENCE: 14 fence shapes (flat, tilde, 4-backtick wrapper, mixed characters, indentation, closer length, trailing text, unclosed) strip exactly as CommonMark fences do"
}
h_repo() { # M-REPO a non-default repository argument is used in BOTH the permission URL and the issue read; the default repo is never touched
  mkc "$SB/h.json" priv-op "S2-ACTIVATED: $T2" "$T2"; mkp 'priv-op\tadmin\n'
  REPO_EXP=other/repo run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv" other/repo
  local pos=0; if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out "S2-ACTIVATED: $T2" && grep -qxF 'issue 9818' "$SB/req.log" && grep -qxF 'perm priv-op' "$SB/req.log"; then pos=1; fi
  REPO_EXP=other/repo run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( pos )) && (( RAW_MISS == 1 )); then pass "M-REPO: repo other/repo is used for the issue read AND the permission URL; a call without it asks the DEFAULT repo and the stub refuses it"
  else fail "M-REPO: other/repo call ok=$pos; default-repo twin miss=$RAW_MISS (want 1)"; fi
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
  printf '%s\n' '{"comments":[{"author":null,"authorAssociation":"OWNER","body":"RESULT: PASS","createdAt":"'"$T1"'"},{"author":{"login":"priv-op"},"authorAssociation":"CONTRIBUTOR","body":"keep","createdAt":"'"$T2"'"}]}' > "$SB/h.json"
  mkp 'priv-op\tadmin\n'
  run_case_raw trusted_verdict_comments 9818 "$SB/h.json" "$SB/pm.tsv"
  if (( RAW_MISS == 0 )) && [[ "$RAW_RC" == 0 ]] && in_out keep && ! in_out 'RESULT: PASS' && [[ "$(nreq perm)" == 1 ]]; then
    pass "M-NULLAUTH: a comment with author null is dropped and the rest of the thread is read"
  else fail "M-NULLAUTH: rc=$RAW_RC miss=$RAW_MISS out=[$RAW_OUT]"; fi
}
LIB_ROWS=(h_h1 h_h2 h_h3 h_h4_parity h_h4_abs h_h5 h_h6 h_h7 h_h8 h_h9 h_h10 h_crlf h_h11 h_big h_recfail h_fsm h_repo h_case h_login_shape h_null_author)
for _r in "${LIB_ROWS[@]}"; do "$_r"; done

# --- harness integrity: a stub that answers `admin` to EVERYONE must redden the negative rows (the rows can fail) ----------
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
  "    out=\"\${out}\${rec}\"\$${Q}\\n${Q}" \
  "    printf '%s\\n' \"\$body\"; out=\"\${out}\${rec}\"\$${Q}\\n${Q}"
# EQUIVALENT single edits (measured: each survives every row above, so neither is a mutant on its own): turning the memo guard off alone, or `sort -u` into `cat` alone, each leave exactly one
# request per distinct author because the OTHER one still deduplicates. Only the two together are a mutant.
mutant_lib m-no-dedupe       "h_h8" '  if [[ -n "${_TRUSTED_VERDICT_PERM[$key]:-}" ]]; then' '  if false; then' \
  '    done | sort -u)"' '    done | cat)"'
mutant_lib m-first-page      "h_h9" '        .comments[]' '        .comments[0:100][]'
mutant_lib m-t-empty         "h_h5" "${Q}{t: \$t, b: .}${Q}" "${Q}{t: \"\", b: .}${Q}"
mutant_lib m-validate-in-core "h_h5" '    _trusted_verdict_is_trusted_perm "$perm" || continue' '    _trusted_verdict_is_trusted_perm "$perm" || continue
    [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 2'
mutant_lib m-second-read     "h_h10" '  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  if ! jq -e -s' '  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  gh issue view "$issue" --repo "$repo" --json comments --jq ".comments[].body" >/dev/null 2>&1
  [[ -n "$records" ]] || return 0
  if ! jq -e -s'
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
cp "$LIB" "$SB/identity.sh"
lib_rows_quiet "$SB/identity.sh" "${LIB_ROWS[@]}"
if (( MUT_REDS == 0 && MUT_CRASHED == 0 )); then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an unmutated copy of the lib turns no row red over the full row set"
else fail "harness control: the identity copy turned $MUT_REDS row(s) red (crashed=$MUT_CRASHED): the harness is polluted"; fi
# the verdict itself: an inert mutant fed through mutant_lib must be REPORTED as a survivor and must make the suite red (counters restored after)
_p0=$PASS; _f0=$FAIL; _r0=$MUT_RUN; _c0=$MUT_CAUGHT
mutant_lib c-inert "h_h2 h_h3" "$PRED" '    admin|maintain|write) return 0; ;;' >"$SB/inert.out"
_inert_fails=$((FAIL - _f0)); _inert_caught=$((MUT_CAUGHT - _c0))
PASS=$_p0; FAIL=$_f0; MUT_RUN=$_r0; MUT_CAUGHT=$_c0
if (( _inert_fails == 1 && _inert_caught == 0 )) && grep -q 'SURVIVED' "$SB/inert.out"; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an inert mutant is reported SURVIVED and makes the suite red"
else fail "harness control: an inert mutant was not reported as a survivor (fails=$_inert_fails caught=$_inert_caught)"; fi
if (( CTRL_OK != 5 )); then fail "harness controls: $CTRL_OK of 5 held"; fi
if (( MUT_RUN == MUT_CAUGHT && MUT_RUN >= 27 )); then pass "LIB MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "LIB MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 27)"; fi

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
MIN_ASSERTIONS=66
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
