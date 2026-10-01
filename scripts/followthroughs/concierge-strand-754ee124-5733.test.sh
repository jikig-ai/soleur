#!/usr/bin/env bash
# Exit-code harness for concierge-strand-754ee124-5733.sh (tracking issue #5733).
#
# The probe's exit code makes the nightly sweeper act on a PUBLIC-repo tracker: exit 0 closes
# #5733. So the cases here are the ways that verdict can be forged, wedged or dropped — not the
# happy path, which is one line.
#
# ASSEMBLY UNDER TEST: this probe plus scripts/lib/trusted-verdict.sh. The lib has its own
# matrix (scripts/lib/trusted-verdict.test.sh) that outlives any one consumer; this file is the
# per-probe half — it asserts that THIS probe wires the lib in and maps its three outcomes onto
# the sweeper's exit contract. Both halves are needed: the lib's matrix cannot see a probe that
# sources it and then ignores the result.
#
# THE STUB RUNS REAL jq AND REFUSES ARGV IT DID NOT EXPECT. A stub that answers the same fixture
# regardless of its arguments puts the fixture seam ABOVE the code under test, so it cannot
# detect the probe asking the wrong question. Unexpected invocations exit 64 and are echoed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/concierge-strand-754ee124-5733.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

fails=0; passes=0
# `cases` is incremented at the CALL SITE, never inside pass()/fail() — that placement is the
# whole substance of the conservation check at the bottom. Incrementing inside the verdict
# helpers makes the count move WITH the verdict, so a neutered fail() drops the row and its
# count together and the floor stays satisfied.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required for the stub" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR%/}/strand-5733.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" || { echo "FATAL: mkdir failed" >&2; exit 1; }

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${GH_RC:-0}" == "0" ]] || exit "${GH_RC}"
if [[ "${1:-}" == "api" ]]; then
  ep="${2:-}"
  case "$ep" in
    repos/jikig-ai/soleur/collaborators/*/permission) : ;;
    *) printf 'STUB-UNEXPECTED: gh api %s\n' "$ep" >&2; exit 64 ;;
  esac
  login="${ep#*/collaborators/}"; login="${login%/permission}"
  perm="$(printf '%s\n' "${PERMS:-}" | awk -F'=' -v l="$login" '$1==l{print $2}')"
  # Absent from $PERMS == GitHub's "not a user" 404: definitive, drop that author.
  if [[ -z "$perm" ]]; then printf 'gh: %s is not a user (HTTP 404)\n' "$login" >&2; exit 1; fi
  # The literal 403 == the read FAILED: TRANSIENT, absence is not evidence.
  if [[ "$perm" == "403" ]]; then printf 'gh: Resource not accessible by integration (HTTP 403)\n' >&2; exit 1; fi
  printf '%s\n' "$perm"; exit 0
fi
[[ "${1:-}" == "issue" && "${2:-}" == "view" ]] || { printf 'STUB-UNEXPECTED: gh %s\n' "$*" >&2; exit 64; }
[[ "${3:-}" == "5733" ]] || { printf 'STUB-UNEXPECTED: wrong issue %s\n' "${3:-}" >&2; exit 64; }
printf '%s' "$*" | grep -q -- '--repo jikig-ai/soleur' || { printf 'STUB-UNEXPECTED: no --repo: %s\n' "$*" >&2; exit 64; }
jqexpr=""; want=""; prev=""
for a in "$@"; do
  [[ "$prev" == "--jq"   ]] && jqexpr="$a"
  [[ "$prev" == "--json" ]] && want="$a"
  prev="$a"
done
case "$want" in
  comments) printf '%s' "${COMMENTS_JSON:-{\"comments\":[]\}}" | jq -r "$jqexpr" ;;
  *)        printf 'STUB-UNEXPECTED: --json %s\n' "$want" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# Roles -> the login + effective permission the lib actually resolves. The row labels stay
# semantic (OPERATOR / COLLABORATOR / STRANGER / BOT) so each case says what it is about.
PERMS='operator=admin
reviewer=write
drive-by=none'
export PERMS

comments_json() { # <ROLE>:<body> ...
  local out="[]" a b login
  for spec in "$@"; do
    a="${spec%%:*}"; b="${spec#*:}"
    case "$a" in
      OPERATOR)     login="operator" ;;
      COLLABORATOR) login="reviewer" ;;
      STRANGER)     login="drive-by" ;;
      BOT)          login="github-actions" ;;   # absent from PERMS -> HTTP 404
      *) printf 'FATAL: unknown role %s\n' "$a" >&2; exit 1 ;;
    esac
    out="$(jq -c --arg a "$login" --arg b "$b" '. + [{author:{login:$a}, body:$b}]' <<<"$out")"
  done
  jq -c '{comments: .}' <<<"$out"
}

run() { # run <comments_json> [gh_rc] [perms_override]
  OUT="$(COMMENTS_JSON="$1" GH_RC="${2-0}" PERMS="${3-$PERMS}" \
         PATH="$WORK/bin:$PATH" bash "$PROBE" 2>&1)"
  RC=$?
  if [[ "$OUT" == *STUB-UNEXPECTED* ]]; then RC="stub-miss"; fi
}

expect() { local l="$1" wrc="$2" wsub="$3"
  cases=$((cases + 1))
  if [[ "$RC" != "$wrc" ]]; then fail "$l — wanted rc=$wrc, got rc=$RC. Output: $OUT"; return; fi
  if [[ -n "$wsub" && "$OUT" != *"$wsub"* ]]; then fail "$l — rc ok but output lacks '$wsub'. Output: $OUT"; return; fi
  pass "$l (rc=$RC)"
}

echo "concierge-strand-754ee124-5733 harness"

# 1. The happy path: the operator confirms the strand is healed.
run "$(comments_json 'OPERATOR:RESULT: PASS  retried /soleur:go on 754ee124, no strand')"
expect "an operator PASS closes the tracker" 0 ""

# 2. A recorded regression must reopen, not close.
run "$(comments_json 'OPERATOR:RESULT: FAIL  still stranding on the same workspace')"
expect "an operator FAIL is exit 1" 1 "strand persists"

# 3. Nothing yet — the common state, and never a pass.
run "$(comments_json 'OPERATOR:Chased this, will retry after the deploy.')"
expect "no verdict is exit 1, not 0" 1 "no RESULT: PASS/FAIL verdict"

# ── FORGERY ──────────────────────────────────────────────────────────────────────────
# 4. THE CRITICAL ONE. Public repo, issues open: one HTTP POST of `RESULT: PASS` from any
#    authenticated user must not close the tracker (#7448).
run "$(comments_json 'STRANGER:RESULT: PASS  looks fine to me')"
expect "a stranger's PASS does NOT close the tracker" 1 "no RESULT: PASS/FAIL verdict"

# 5. ...and the filter must not be so tight it drops a real reviewer.
run "$(comments_json 'COLLABORATOR:RESULT: PASS  confirmed on my retry too')"
expect "a write-permission collaborator's verdict IS honoured" 0 ""

# 6. A stranger cannot wedge the tracker red either.
run "$(comments_json 'STRANGER:RESULT: FAIL  broken for me')"
expect "a stranger's FAIL does not wedge the tracker" 1 "no RESULT: PASS/FAIL verdict"

# ── THE #6617 REGRESSION THIS LIB EXISTS FOR ─────────────────────────────────────────
# 7. PRIVATE ORG MEMBERSHIP. Under the sweeper's GITHUB_TOKEN the operator renders as
#    `authorAssociation: CONTRIBUTOR`, so the old inline filter dropped their verdict and the
#    tracker stayed red forever (#6617, two months). Effective permission does not depend on
#    membership visibility, so the same comment must now be honoured. This fixture carries NO
#    authorAssociation field at all — under the old mechanism it could not pass.
run "$(comments_json 'OPERATOR:RESULT: PASS  verified after the deploy')"
expect "a verdict from an author with private org membership is honoured" 0 ""

# ── PLUMBING ─────────────────────────────────────────────────────────────────────────
# 8. A bot comment (HTTP 404, "not a user") must be DROPPED without wedging the read. Every
#    tracker here carries `github-actions` comments, so reading 404 as TRANSIENT would make
#    the probe permanently unresolvable — the same permanent-red outcome, from the other side.
run "$(comments_json 'BOT:sweeper output, ignore' 'OPERATOR:RESULT: PASS  healed')"
expect "a 404 'not a user' author is dropped, not treated as a failed read" 0 ""

# 9. ...but a 403 on the permission read IS a failed read.
run "$(comments_json 'OPERATOR:RESULT: PASS  healed')" 0 'operator=403'
expect "a 403 permission read is TRANSIENT, never a pass" 2 "TRANSIENT"

# 10. gh transport failure must never read as "no verdict, therefore fine".
run "$(comments_json 'OPERATOR:RESULT: PASS  healed')" 7
expect "gh transport failure is TRANSIENT, not a pass" 2 "TRANSIENT"

# 11. A fenced template must not arm the probe.
run "$(comments_json 'OPERATOR:Post one of these when you retry:
```
RESULT: PASS
```
Not done yet.')"
expect "a fenced template does not close the tracker" 1 "no RESULT: PASS/FAIL verdict"

# 12. Word boundary: `RESULT: PASSing` explicitly declines to verify.
run "$(comments_json 'OPERATOR:RESULT: PASSing on this until the deploy lands')"
expect "RESULT: PASSing does not close the tracker" 1 "no RESULT: PASS/FAIL verdict"

# 13. Last trusted verdict wins, in the direction that a FAIL-absorbing rule gets wrong.
run "$(comments_json 'OPERATOR:RESULT: FAIL  still stranding' \
                     'OPERATOR:RESULT: PASS  fixed by the follow-up deploy')"
expect "a later corrected PASS overrides an earlier FAIL" 0 ""

# --- Anti-vacuity floor ---------------------------------------------------------------
# Reported with printf + exit DIRECTLY, never by incrementing `fails` — `fails` is what the
# exit status reads, so a floor enforced through it cannot witness a neutered verdict helper.
# Measured from a green run with zero slack: 13 expect() rows.
MIN_CHECKS=13
if (( cases < MIN_CHECKS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CHECKS" >&2
  echo "concierge-strand-754ee124-5733: $passes/$cases passed"
  exit 1
fi

# --- Accounting conservation ----------------------------------------------------------
# The floor above catches "no assertions RAN". This catches "assertions ran and their verdicts
# were discarded": `cases` keeps its full value when fail() is a no-op, and every assertion
# records exactly one verdict, so passes+fails MUST equal cases.
if (( passes + fails != cases )); then
  printf '\n[FATAL] accounting: %d pass + %d fail != %d case(s) — a verdict helper was neutered.\n' \
    "$passes" "$fails" "$cases" >&2
  exit 1
fi

echo "concierge-strand-754ee124-5733: $passes/$cases passed"
(( fails == 0 )) || exit 1
