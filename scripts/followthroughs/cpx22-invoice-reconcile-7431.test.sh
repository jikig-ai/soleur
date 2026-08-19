#!/usr/bin/env bash
# Exit-code harness for cpx22-invoice-reconcile-7431.sh (tracking issue #7437).
#
# The probe decides whether a production financial ledger stands or gets corrected, from free text
# typed into a GitHub comment on a PUBLIC repo. Exit 0 auto-closes the tracker. So the cases here
# are chosen against the ways that verdict can be forged, poisoned, or wedged — not against the
# happy path, which is one line.
#
# THE STUB RUNS REAL jq. An earlier version returned a canned body string and ignored the probe's
# `--jq` argument, which would have made the author filter — the fix for the critical finding —
# structurally untestable: the filter would have been asserted by a fixture that never applied it.
# That is the "a fixture can only falsify assumptions its author did not share" failure this PR's
# own learning doc is about, so the stub feeds the probe's real jq expression over a real comments
# payload. It also asserts the flags it is passed, because a probe wedged at TRANSIENT by a wrong
# flag is a tracker that never closes and an alarm that never fires (#6288 sat open a month on
# exactly that), and no assertion about verdicts can see it.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/cpx22-invoice-reconcile-7431.sh"
fails=0
passes=0
# `cases` is incremented at the CALL SITE — at the top of expect(), and inline for the one
# assertion that does not go through it — and NEVER inside pass()/fail(). That placement is the
# whole substance of the conservation check at the bottom of this file. The previous shape
# incremented `checks` inside BOTH verdict helpers, so it moved WITH the verdict: stubbing
# `fail() { :; }` dropped the row and its count together, the cardinality floor stayed satisfied
# at 16, and a forged-verdict regression printed `16/16 passed` and exited 0.
#
# Never increment inside `$( )` — a subshell discards it.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required for the stub" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# gh stub. `issue view --json body` -> $ISSUE_BODY. `issue view --json comments --jq <expr>` ->
# runs the REAL expr over $COMMENTS_JSON, so the authorAssociation filter is genuinely exercised.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${GH_RC:-0}" == "0" ]] || exit "${GH_RC}"
jqexpr=""; want=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--jq"   ]] && jqexpr="$a"
  [[ "$prev" == "--json" ]] && want="$a"
  prev="$a"
done
case "$want" in
  body)     printf '%s' "${ISSUE_BODY:-}" ;;
  comments) printf '%s' "${COMMENTS_JSON:-{\"comments\":[]\}}" | jq -r "$jqexpr" ;;
  *)        exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

DIRECTIVE='<!-- soleur:followthrough script=scripts/followthroughs/cpx22-invoice-reconcile-7431.sh earliest=2026-09-03 secrets=GH_TOKEN -->'

# comments_json <assoc>:<body> ...  -> a --json comments payload
comments_json() {
  local out="[]" a b
  for spec in "$@"; do
    a="${spec%%:*}"; b="${spec#*:}"
    out="$(jq -c --arg a "$a" --arg b "$b" '. + [{authorAssociation:$a, body:$b}]' <<<"$out")"
  done
  jq -c '{comments: .}' <<<"$out"
}

run() { # run <comments_json> [issue_body] [gh_rc]
  OUT="$(COMMENTS_JSON="$1" ISSUE_BODY="${2-$DIRECTIVE}" GH_RC="${3-0}" \
         PATH="$WORK/bin:$PATH" bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { local l="$1" wrc="$2" wsub="$3"
  # One assertion is about to be decided. Counted HERE, outside pass()/fail(), so it survives a
  # neutered verdict helper and the conservation check below can see the missing verdict.
  cases=$((cases + 1))
  if [[ "$RC" != "$wrc" ]]; then fail "$l — wanted rc=$wrc, got rc=$RC. Output: $OUT"; return; fi
  if [[ -n "$wsub" && "$OUT" != *"$wsub"* ]]; then fail "$l — rc ok but output lacks '$wsub'. Output: $OUT"; return; fi
  pass "$l (rc=$RC)"
}

echo "cpx22-invoice-reconcile-7431 harness"

# 1. The shape the issue asks for. A `$`-anchored probe would reject the figure and never close.
run "$(comments_json 'MEMBER:RESULT: PASS  EUR 13.98 delta, gross == net, no VAT correction')"
expect "member PASS with the required figure closes" 0 "PASS"

# 2. FAIL reopens and names the both-ledgers consequence.
run "$(comments_json 'MEMBER:RESULT: FAIL  invoice still shows the cx23 rate')"
expect "member FAIL is exit 1" 1 "expenses.md AND cost-model.md"

# 3. Nothing yet — the overwhelmingly common state, and never a pass.
run "$(comments_json 'MEMBER:Chased ops@ for the PDF, nothing yet.')"
expect "no verdict is TRANSIENT" 2 "no member-authored"

# ── FORGERY ──────────────────────────────────────────────────────────────────────────────────
# 4. THE CRITICAL ONE. Public repo: any GitHub user can comment. A NONE/CONTRIBUTOR verdict must
#    not close a financial tracker. Before the author filter this exited 0 on one HTTP POST.
run "$(comments_json 'NONE:RESULT: PASS  EUR 19.49, VAT unchanged')"
expect "a stranger's PASS does NOT close the issue" 2 "no member-authored"

# 5. ...and the filter must not be so tight it rejects real reviewers.
run "$(comments_json 'COLLABORATOR:RESULT: PASS  EUR 14.00 confirmed')"
expect "a COLLABORATOR verdict is accepted" 0 "PASS"

# 6. A stranger cannot fabricate a FAIL either — wedging the tracker red is also an attack.
run "$(comments_json 'NONE:RESULT: FAIL  nope')"
expect "a stranger's FAIL does not wedge the tracker" 2 "no member-authored"

# ── ANCHORING ────────────────────────────────────────────────────────────────────────────────
# 7. The word boundary. `RESULT: PASSing on this for now` exited 0 before `\b` — closing the
#    tracker on a comment that explicitly DECLINES to verify.
run "$(comments_json 'MEMBER:RESULT: PASSing on this for now, invoice not here yet')"
expect "RESULT: PASSing does not close" 2 "no member-authored"

# 8. Evidence required. The header and the issue both promise a bare verdict is refused.
run "$(comments_json 'MEMBER:RESULT: PASS')"
expect "bare PASS with no figure is TRANSIENT" 2 "no figure"

# 9. A fenced template must not arm the probe. This is a helpful contributor, not an attacker —
#    and case 10 shows the unindented paste is the realistic one.
run "$(comments_json 'MEMBER:Use this form:
```
RESULT: PASS   <actual figure, and any VAT correction>
```
Asking before the invoice lands.')"
expect "a fenced template does not close the issue" 2 "no member-authored"

# 10. Mid-sentence mention — the easy anchoring case, kept as the cheap regression.
run "$(comments_json 'MEMBER:Do I write RESULT: PASS once the invoice lands?')"
expect "an inline mention does not close the issue" 2 "no member-authored"

# ── VERDICT SELECTION ────────────────────────────────────────────────────────────────────────
# 11. Retraction of a premature PASS. FAIL must win here.
run "$(comments_json 'MEMBER:RESULT: PASS  looked right at first glance' \
                     'MEMBER:RESULT: FAIL  retracting: that was July, August bills cx23')"
expect "a later FAIL overrides an earlier PASS" 1 "FAIL"

# 12. THE INVERSE, and the reason this is last-wins rather than FAIL-absorbing. Under the old rule
#     a premature FAIL was unrecoverable: exit 1 on every sweep forever, tracker permanently red.
#     Note case 11 alone cannot distinguish the two rules — this case is what makes the choice
#     observable, and "FAIL always wins" fails here.
run "$(comments_json 'MEMBER:RESULT: FAIL  invoice shows cx23' \
                     'MEMBER:RESULT: PASS  corrected invoice reissued, EUR 14.00 delta confirmed')"
expect "a later corrected PASS overrides an earlier FAIL" 0 "PASS"

# 13. SELF-POISONING. The sweeper posts this probe's own stdout into a comment on this issue. If
#     the echoed verdict keeps its `RESULT:` anchor at column 1, the next run reads the sweeper's
#     echo as a verdict and the issue can never close again. Simulates that exact comment.
run "$(comments_json 'MEMBER:RESULT: FAIL  invoice shows cx23' \
                     'MEMBER:### Sweeper run: FAIL
cpx22-invoice-reconcile[#7437]: FAIL — the invoice contradicts the ledger
RESULT: FAIL  invoice shows cx23' \
                     'MEMBER:RESULT: PASS  corrected invoice, EUR 14.00 delta confirmed')"
expect "the sweeper's own echoed FAIL does not outlive the operator's correction" 0 "PASS"

# 14. And the probe must not EMIT a re-readable anchor in the first place.
run "$(comments_json 'MEMBER:RESULT: FAIL  invoice shows cx23')"
cases=$((cases + 1))
if [[ "$OUT" == *$'\n''RESULT: FAIL'* || "$OUT" == 'RESULT: FAIL'* ]]; then
  fail "the probe echoes an unredacted ^RESULT: line, which the sweeper will post back and re-read"
else
  pass "the echoed verdict is redacted so it cannot be re-read as one"
fi

# ── PLUMBING ─────────────────────────────────────────────────────────────────────────────────
# 15. gh transport failure must never read as "no verdict, therefore fine". Untestable before,
#     because the old stub's view arm always exited 0.
run "$(comments_json 'MEMBER:RESULT: PASS  EUR 14.00')" "$DIRECTIVE" 7
expect "gh transport failure is TRANSIENT, not a pass" 2 "TRANSIENT"

# 16. The hardcoded issue number is asserted against the directive, so a retarget is caught rather
#     than silently reading a stale thread.
run "$(comments_json 'MEMBER:RESULT: PASS  EUR 14.00')" "this issue no longer tracks that script"
expect "a tracker missing its directive is TRANSIENT" 2 "no longer carries"

# --- Anti-vacuity floor -----------------------------------------------------------------------
# This harness's own dispatch. A fixture builder that no-ops, an early `return`, a `run()` that
# stops invoking the probe — any of these leaves the suite asserting nothing about a probe that
# decides whether a production financial ledger stands.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never by incrementing `fails`. The previous
# shape did `fails=$((fails + 1))`, and `fails` is exactly what the exit status reads — so
# neutering the verdict machinery silenced the rows AND the floor that exists to notice the
# silence. A floor enforced through the suspect cannot witness the suspect.
#
# Measured from a green run with ZERO slack: 16 assertions (15 expect() rows + the inline
# echo-redaction row). Ratchet upward only.
MIN_CHECKS=16
if (( cases < MIN_CHECKS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CHECKS" >&2
  echo "cpx22-invoice-reconcile-7431: $passes/$cases passed"
  exit 1
fi

# --- Accounting conservation --------------------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no
# assertions RAN"; it cannot catch "assertions ran and their verdicts were discarded", because
# `cases` keeps its full value when fail() is a no-op. Every assertion records exactly one
# verdict, so passes+fails MUST equal cases. Reported directly for the same reason as the floor.
if (( passes + fails != cases )); then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if (( passes + fails < cases )); then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a probe failure: add the increment at that call site.\n' >&2
  fi
  echo "cpx22-invoice-reconcile-7431: $passes/$cases passed"
  exit 1
fi

echo "cpx22-invoice-reconcile-7431: $passes/$cases passed"
(( fails == 0 )) || exit 1
