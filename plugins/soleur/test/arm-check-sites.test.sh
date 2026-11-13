#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC1003  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose; a trailing backslash inside single quotes is a literal continuation marker
# Guard 1 of #12656 (plan: knowledge-base/project/plans/2026-11-12-fix-arm-check-drain-prs-product-roadmap-plan.md,
# `## Guard Contract`). Every skill site that arms or re-arms auto-merge binds each arm to the head the
# Review-Evidence arm check set: `--match-head-commit "${H:?...}"` (A1). Only the canonical statement in
# review-evidence-comment.md `## Arm check` sets H (A1-noH), and its body is pinned (A3). There is no exempt arm:
# drain-prs' bot exemption was deleted (CTO ruling R1, 2026-11-13), and A6 keeps its tokens and prose from coming back.
# The admin-merge hatch runs the check and ties it to the head it merges (A7). The two scripts that print re-arm
# instructions route them through the check without an arm of their own, and monitor-pr-checks.sh's
# not-armed line names the check and the hatch by full path (A5).
#
# Two modes:
#   bash arm-check-sites.test.sh              driver: real-tree verdict, then the H8 control, mutation and harness rows
#   bash arm-check-sites.test.sh --root <dir> one assertion run over <dir>; prints FAIL[<id>] lines and a LEDGER line
# --root exit: 0 = ledger is exactly EXPECTED_LEDGER and nothing failed; 1 = an assertion failed;
#              2 = the instrument broke (python error, missing ledger ID). A row counts as caught only on exit 1
#              naming its expected ID and reason; exit 2 or higher is an instrument failure, never a pass.
# A scanner that finds no span at all is caught by A1-floor (every site needs one), so there is no separate zero check.
#
# Contract. This is a TEXT guard over a fixed site list: it proves each listed site's arm text carries the pin outside
# any substitution, and that the hatch's gate lines are present whole and in order. It is not a shell parser and does
# not prove the text runs. Stated residuals (a later shape inside one is "covered by R<n>", not a new finding):
#   R1 a gate line or arm hidden by a construct that keeps its text intact (a heredoc, a function never called,
#      an `if false`); R2 quote-state tricks inside a joined line (nested quotes inside a quoted substitution);
#   R3 arm or merge sites outside SITES, LINK_ONLY and the A5 scripts (repo-wide walker: #12739);
#   R4 runtime properties the canonical check owns (what EV and H resolve to): proven by the dry runs, not here.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SITES=(
  plugins/soleur/skills/ship/SKILL.md
  plugins/soleur/skills/merge-pr/SKILL.md
  plugins/soleur/skills/drain-prs/SKILL.md
  plugins/soleur/skills/product-roadmap/SKILL.md
  plugins/soleur/skills/ship/references/merge-queue-dequeue.md
)
# Sites that must link the check but run no --auto arm (the admin-merge hatch gates an --admin merge).
LINK_ONLY=(plugins/soleur/skills/ship/references/settle-then-admin-merge.md)
SETTLE="${LINK_ONLY[0]}"
DRAIN=plugins/soleur/skills/drain-prs/SKILL.md
CANON=plugins/soleur/skills/review/references/review-evidence-comment.md
SYNC=plugins/soleur/scripts/sync-pr-behind.sh
MQJ=scripts/merge-queue-jump.sh
MON=plugins/soleur/scripts/monitor-pr-checks.sh
SETTLE_PATH=plugins/soleur/skills/ship/references/settle-then-admin-merge.md
LINK='review-evidence-comment.md#arm-check'
EXPECTED_LEDGER='A1 A1-floor A1-noH A2 A2b A3 A5 A6 A7'
# A1-noH: no site file assigns H. The `-` in the first class keeps `gh api -H=...` quiet (H7).
NOH_RE='(^|[^A-Za-z0-9_-])H(\+?=|\[[^]]*\]=)|\$\{H:?=|(read|declare|typeset|export|local|readonly|mapfile|readarray|for)([[:space:]]+[^;&|]*)?[[:space:]]H([[:space:]=;]|$)|printf[[:space:]]+-v[[:space:]]*H'
CANON_REFUSE='|| { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }'
CANON_ARM='--match-head-commit "${H:?run the arm check in this call}"'
# A3: the check's load-bearing fragments, each a literal that must appear in the canonical file.
CANON_BODY=(
  'EV=$(gh pr view PR_NUMBER --json comments --jq '"'"'[.comments[].body|select(test("^\\s*review-evidence:";"i"))]|last // ""|split("\n")[0]|select(test("; coverage=full[; ]") and test("; unresolved-P1-P2=0([; ]|$)") and ([scan("coverage=")]|length==1) and ([scan("unresolved-P1-P2=")]|length==1))|capture("^Review-Evidence: head=(?<h>[0-9a-f]{7,40})[; ]").h'"'"') \'
  '&& git merge-base --is-ancestor "$EV" "$H" \'
  '&& R=$(git rev-list --first-parent --no-merges "$EV..$H") && [ -z "$R" ] \'
)
# A6: the deleted exempt arm's tokens (anywhere under plugins/soleur/skills/) and its prose (in the site files and
# the canonical file only, case-insensitive, with a left boundary so "non-exempt arm" elsewhere stays quiet).
TOMB_RE='EXEMPT_HEAD|EXEMPT_ARM|EXEMPT_READ|soleur-exempt-|DOMAIN_SURFACE_RE'
TOMB_PROSE_RE='(^|[^a-z0-9_-])(exempt(ed)?[ -](read|arm|bot prs?|prs?)([^a-z]|$)|bot exemption|exempt from the arm check)'
# A7: the admin-merge hatch's gate lines, in this order, before admin-merge-ready.sh in each readiness fence.
SETTLE_FETCH='git fetch -q origin "pull/<N>/head" || {'
SETTLE_PLACE="# REPLACE THIS LINE with the arm check's first statement (review-evidence-comment.md#arm-check)"
SETTLE_TIE='[ "${H:?run the arm check in this call}" = "$SHA" ] || {'
# A7 compares whole lines (indent stripped), so a commented-out or neutered gate line is a missing one.
SETTLE_FETCH_LINE='git fetch -q origin "pull/<N>/head" || { echo "ADMIN-MERGE ABORTED: could not fetch the PR head"; exit 1; }'
SETTLE_TIE_LINE='[ "${H:?run the arm check in this call}" = "$SHA" ] || { echo "ADMIN-MERGE ABORTED: evidence head check read a different head"; exit 4; }'

# scan <root> <relpath>... : one `ARM<TAB>rel<TAB>line<TAB>depth-0 text<TAB>span` line per arm span; exit 3 on a python error.
scan() {
  local root="$1"; shift
  python3 -I - "$root" "$@" <<'PY'
import os, re, sys
root, rels = sys.argv[1], sys.argv[2:]
tok = re.compile(r"(?<![A-Za-z0-9_-])gh\s+pr\s+merge(?![A-Za-z0-9_-])")
auto = re.compile(r"(?<![A-Za-z0-9_-])--auto(?![A-Za-z0-9_-])")
def joined(text):
    # (first line number, joined line, inside a ``` fence) per logical line
    out, buf, start, fence = [], "", None, False
    for n, line in enumerate(text.split("\n"), 1):
        if start is None and re.match(r"[ \t]*```", line):
            fence = not fence
            out.append((n, line, False)); continue
        if start is None:
            start = n
        m = re.search(r"\\[ \t]*$", line)
        if m:
            buf += line[:m.start()] + " "
            continue
        out.append((start, buf + line, fence)); buf, start = "", None
    if start is not None:
        out.append((start, buf, fence))
    return out
def span(line, i, nxt, fence):
    # From the token to the first unquoted ; && || | ) or ` #` outside any substitution, an unescaped
    # backtick outside a fence (inline code), the next token, or the end of the joined line. `$(`, `$((`,
    # `(` and, inside a fence, a backtick open a substitution level (a quote state is saved per level);
    # a backslash escapes the next character outside single quotes. Returns (span, depth-0 text): a pin
    # that only appears inside a substitution aborts that subshell, never the arm.
    q, j, stack, top = None, i, [], []
    while j < nxt:
        c, d0 = line[j], not stack
        if c == "`" and (j == 0 or line[j - 1] != "\\"):
            if not fence:
                break
            if q != "'":
                if stack and stack[-1][0] == "`":
                    q = stack.pop()[1]
                else:
                    stack.append(("`", q)); q = None
                j += 1; continue
        if q == "'":
            if c == "'":
                q = None
        elif c == "\\":
            if d0:
                top.append(line[j:j + 2])
            j += 2; continue
        elif line.startswith("$(", j):
            stack.append(("(", q)); q = None; j += 2; continue
        elif q == '"':
            if c == '"':
                q = None
        elif c in "\"'":
            q = c
        elif c == "(":
            stack.append(("(", None)); j += 1; continue
        elif c == ")" and stack and stack[-1][0] == "(":
            q = stack.pop()[1]; j += 1; continue
        elif d0 and (c in ";|)" or line.startswith("&&", j) or (c == "#" and j > 0 and line[j - 1] in " \t")):
            break
        if d0:
            top.append(c)
        j += 1
    return line[i:j], "".join(top)
for rel in rels:
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        print("MISSING\t" + rel); continue
    with open(p, encoding="utf-8") as fh:
        text = fh.read()
    for n, line, fence in joined(text):
        hits = [m.start() for m in tok.finditer(line)]
        for k, i in enumerate(hits):
            s, top = span(line, i, hits[k + 1] if k + 1 < len(hits) else len(line), fence)
            if auto.search(s):
                print("ARM\t%s\t%d\t%s\t%s" % (rel, n, top.replace("\t", " "), s.replace("\t", " ")))
PY
  local rc=$?; (( rc == 0 )) || return 3
}

# run_root <root> : the assertion run. Prints FAIL[<id>] lines and `LEDGER <ids>`; returns 0/1/2.
run_root() {
  local root="$1" f=0 out rel n c canon_hits rc kind s l frag got ledger=()
  local -A per_file=()
  out=$(scan "$root" "${SITES[@]}") || { echo "INSTRUMENT scanner (python) failed"; return 2; }

  # A1 -- every arm span carries the H pin.
  ledger+=(A1)
  while IFS=$'\t' read -r kind rel n top s; do
    [[ "$kind" == ARM ]] || continue
    per_file[$rel]=$(( ${per_file[$rel]:-0} + 1 ))
    c=$(grep -o -- '--match-head-commit' <<<"$s" | wc -l)
    if [[ "$top" != *'--match-head-commit "${H:?'* ]]; then echo "FAIL[A1] $rel:$n arm without the \${H:?} pin outside a substitution: $s"; f=1
    elif (( c != 1 )); then echo "FAIL[A1] $rel:$n arm with $c --match-head-commit flags (want 1): $s"; f=1; fi
  done <<<"$out"

  # A1-floor -- set identity: every site present, each with at least one arm span.
  ledger+=(A1-floor)
  for rel in "${SITES[@]}"; do
    if grep -q "^MISSING	$rel\$" <<<"$out"; then echo "FAIL[A1-floor] missing site file: $rel"; f=1
    elif (( ${per_file[$rel]:-0} < 1 )); then echo "FAIL[A1-floor] $rel has no arm span"; f=1; fi
  done

  # A1-noH -- only the canonical statement sets H.
  ledger+=(A1-noH)
  for rel in "${SITES[@]}" "${LINK_ONLY[@]}"; do
    [[ -f "$root/$rel" ]] || continue
    c=$(grep -nE -- "$NOH_RE" "$root/$rel"); rc=$?
    (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A1-noH ($rel)"; return 2; }
    [[ -z "$c" ]] || { while IFS= read -r l; do echo "FAIL[A1-noH] $rel:$l"; done <<<"$c"; f=1; }
  done

  # A2 -- every site links the canonical check.
  ledger+=(A2)
  for rel in "${SITES[@]}" "${LINK_ONLY[@]}"; do
    [[ -f "$root/$rel" ]] || { echo "FAIL[A2] missing site file: $rel"; f=1; continue; }
    grep -qF -- "$LINK" "$root/$rel" || { echo "FAIL[A2] $rel does not link $LINK"; f=1; }
  done

  # A2b -- the refusal statement exists once, in the canonical file.
  ledger+=(A2b)
  canon_hits=$(cd "$root" && grep -rlF 'echo "ARM_CHECK refused:' plugins/soleur/skills/); rc=$?
  (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A2b"; return 2; }
  [[ "$canon_hits" == "$CANON" ]] || { echo "FAIL[A2b] refusal statement files: [$(tr '\n' ' ' <<<"$canon_hits")] (want only $CANON)"; f=1; }

  # A3 -- the canonical file carries the refusal statement and the pinned arm line.
  ledger+=(A3)
  if [[ ! -f "$root/$CANON" ]]; then echo "FAIL[A3] canonical file missing: $CANON"; f=1
  else
    grep -qF -- "$CANON_REFUSE" "$root/$CANON" || { echo "FAIL[A3] canonical refusal statement missing"; f=1; }
    grep -qF -- "$CANON_ARM" "$root/$CANON" || { echo "FAIL[A3] canonical pinned arm line missing"; f=1; }
    for frag in "${CANON_BODY[@]}"; do
      grep -qF -- "$frag" "$root/$CANON" || { echo "FAIL[A3] canonical check fragment missing: $frag"; f=1; }
    done
  fi

  # A5 -- neither script that prints re-arm instructions has an arm span, and each message names the check.
  ledger+=(A5)
  if [[ ! -f "$root/$SYNC" ]]; then echo "FAIL[A5] missing $SYNC"; f=1
  else
    c=$(scan "$root" "$SYNC") || { echo "INSTRUMENT scanner (python) failed on $SYNC"; return 2; }
    [[ -z "$c" ]] || { while IFS=$'\t' read -r _ rel n _ s; do echo "FAIL[A5] $rel:$n arm span: $s"; done <<<"$c"; f=1; }
    c=$(grep -E '^[[:space:]]*tag dequeued 13 ' "$root/$SYNC")
    if [[ -z "$c" ]]; then echo "FAIL[A5] no kind=dequeued message line"; f=1
    else
      [[ "$c" == *merge-queue-dequeue.md* ]] || { echo "FAIL[A5] dequeued message does not name merge-queue-dequeue.md"; f=1; }
      [[ "$c" == *"$LINK"* ]] || { echo "FAIL[A5] dequeued message does not name $LINK"; f=1; }
    fi
  fi
  if [[ ! -f "$root/$MQJ" ]]; then echo "FAIL[A5] missing $MQJ"; f=1
  else
    c=$(scan "$root" "$MQJ") || { echo "INSTRUMENT scanner (python) failed on $MQJ"; return 2; }
    [[ -z "$c" ]] || { while IFS=$'\t' read -r _ rel n _ s; do echo "FAIL[A5] $rel:$n arm span: $s"; done <<<"$c"; f=1; }
    c=$(grep -E '^[[:space:]]*die "PR #\$PR is not in the merge queue and has no auto-merge armed' "$root/$MQJ")
    if [[ -z "$c" ]]; then echo "FAIL[A5] no not-armed die line in $MQJ"; f=1
    else [[ "$c" == *"$LINK"* ]] || { echo "FAIL[A5] $MQJ not-armed message does not name $LINK"; f=1; }; fi
  fi
  if [[ ! -f "$root/$MON" ]]; then echo "FAIL[A5] missing $MON"; f=1
  else
    c=$(scan "$root" "$MON") || { echo "INSTRUMENT scanner (python) failed on $MON"; return 2; }
    [[ -z "$c" ]] || { while IFS=$'\t' read -r _ rel n _ s; do echo "FAIL[A5] $rel:$n arm span: $s"; done <<<"$c"; f=1; }
    c=$(grep -F 'AUTO-MERGE NOT ARMED' "$root/$MON" | grep -F 'printf')
    if [[ -z "$c" ]]; then echo "FAIL[A5] no not-armed printf line in $MON"; f=1
    else
      [[ "$c" == *"plugins/soleur/skills/review/references/$LINK"* ]] || { echo "FAIL[A5] $MON not-armed line does not name $LINK by full path"; f=1; }
      [[ "$c" == *"$SETTLE_PATH"* ]] || { echo "FAIL[A5] $MON not-armed line does not name $SETTLE_PATH"; f=1; }
    fi
  fi

  # A6 -- tombstone: the deleted exempt arm's tokens appear nowhere under plugins/soleur/skills/.
  ledger+=(A6)
  c=$(cd "$root" && grep -rnE -- "$TOMB_RE" plugins/soleur/skills/); rc=$?
  (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A6"; return 2; }
  [[ -z "$c" ]] || { while IFS= read -r l; do echo "FAIL[A6] exempt-arm token: $l"; done <<<"$c"; f=1; }
  for rel in "${SITES[@]}" "${LINK_ONLY[@]}" "$CANON"; do
    [[ -f "$root/$rel" ]] || continue
    c=$(grep -niE -- "$TOMB_PROSE_RE" "$root/$rel"); rc=$?
    (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A6 prose ($rel)"; return 2; }
    [[ -z "$c" ]] || { while IFS= read -r l; do echo "FAIL[A6] exempt-arm prose: $rel:$l"; done <<<"$c"; f=1; }
  done

  # A7 -- the hatch: exactly two readiness fences (step 2, carryover), each with fetch, check, tie, then readiness.
  ledger+=(A7)
  if [[ ! -f "$root/$SETTLE" ]]; then echo "FAIL[A7] missing $SETTLE"; f=1
  else
    got=$(FETCH="$SETTLE_FETCH_LINE" PLACE="$SETTLE_PLACE" TIE="$SETTLE_TIE_LINE" python3 -I - "$root/$SETTLE" <<'PY'
import os, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fetch, place, tie = os.environ["FETCH"], os.environ["PLACE"], os.environ["TIE"]
fences = re.findall(r"^[ \t]*```bash\n(.*?)^[ \t]*```", text, re.S | re.M)
ready = [b for b in fences if "admin-merge-ready.sh" in b and "gh pr merge" not in b]
print("COUNT %d" % len(ready))
def first(lines, ok):
    return next((i for i, l in enumerate(lines) if ok(l)), -1)
for k, b in enumerate(ready, 1):
    lines = [l.strip() for l in b.split("\n")]
    want = [(fetch, first(lines, lambda l: l == fetch)), (place, first(lines, lambda l: l.startswith(place))),
            (tie, first(lines, lambda l: l == tie)),
            ("admin-merge-ready.sh", first(lines, lambda l: "admin-merge-ready.sh" in l and not l.startswith("#")))]
    for w, p in want:
        if p < 0:
            print("BLOCK %d missing: %s" % (k, w))
    pos = [p for _, p in want]
    if all(p >= 0 for p in pos) and pos != sorted(pos):
        print("BLOCK %d out of order" % k)
PY
) || { echo "INSTRUMENT A7 parser (python) failed"; return 2; }
    [[ "$got" == *"COUNT 2"* ]] || { echo "FAIL[A7] $SETTLE: want 2 readiness fences, got [${got%%$'\n'*}]"; f=1; }
    while IFS= read -r l; do [[ "$l" == BLOCK* ]] && { echo "FAIL[A7] $SETTLE $l"; f=1; }; done <<<"$got"
  fi

  c="$(printf '%s\n' "${ledger[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  echo "LEDGER $c"
  [[ "$c" == "$EXPECTED_LEDGER" ]] || { echo "INSTRUMENT ledger is not exactly: $EXPECTED_LEDGER"; return 2; }
  return "$f"
}

if [[ "${1-}" == --root ]]; then
  [[ -n "${2-}" && -d "$2" ]] || { echo "INSTRUMENT --root needs a directory" >&2; exit 2; }
  run_root "$2"; exit $?
fi

# ── driver ─────────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
command -v python3 >/dev/null || { echo "[FATAL] python3 required" >&2; exit 2; }

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 2
fi
passes=0; fails=0; FAILED=()

SANDBOX="$(mktemp -d)"
case "$SANDBOX" in /*/*) ;; *) printf '[FATAL] bad sandbox %s\n' "$SANDBOX" >&2; exit 2 ;; esac
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

echo "== real tree: $REPO_ROOT"
real_out=$(bash "$SELF" --root "$REPO_ROOT" 2>&1); real_rc=$?
printf '%s\n' "$real_out"
if (( real_rc != 0 )); then
  printf '[RED] the real tree fails (rc=%s); mutation and harness rows need a GREEN tree and were not run\n' "$real_rc" >&2
  (( real_rc == 1 )) && exit 1 || exit 2
fi
pass "real tree GREEN with ledger"

# One read-only base copy of the site, canonical and script files; each row gets its own writable copy.
BASE="$SANDBOX/base"
for rel in "${SITES[@]}" "${LINK_ONLY[@]}" "$CANON" "$SYNC" "$MQJ" "$MON"; do
  mkdir -p "$BASE/$(dirname "$rel")" && cp "$REPO_ROOT/$rel" "$BASE/$rel" || { echo "[FATAL] base copy of $rel" >&2; exit 2; }
done
chmod -R a-w "$BASE"

edit() { # <file> <old> <new> : exactly-one replacement, or FATAL
  OLD="$2" NEW="$3" python3 -I - "$1" <<'PY' || { echo "[FATAL] edit did not land exactly once in $1" >&2; exit 2; }
import os, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, os.environ["NEW"]))
PY
}
# edit_first <file> <old> <new> : replace the FIRST occurrence (for text the file repeats), or FATAL
edit_first() {
  OLD="$2" NEW="$3" python3 -I - "$1" <<'PY' || { echo "[FATAL] edit_first found no occurrence in $1" >&2; exit 2; }
import os, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); o = os.environ["OLD"]
if o not in s: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, os.environ["NEW"], 1))
PY
}

# edit_all <file> <old> <new> : replace every occurrence (at least one), or FATAL
edit_all() {
  OLD="$2" NEW="$3" python3 -I - "$1" <<'PY' || { echo "[FATAL] edit_all found no occurrence in $1" >&2; exit 2; }
import os, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); o = os.environ["OLD"]
if o not in s: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, os.environ["NEW"]))
PY
}

# row <id> <want: GREEN | assertion id> <fn> [reason: a substring the FAIL[<id>] line must carry; required unless GREEN]
row() {
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1" want="$2" fn="$3" why="${4-}" t out rc
  t="$SANDBOX/row-$id"; rm -rf "$t"; cp -r "$BASE" "$t" && chmod -R u+w "$t" || { echo "[FATAL] row copy $id" >&2; exit 2; }
  "$fn" "$t"
  out=$(bash "$SELF" --root "$t" 2>&1); rc=$?
  if [[ "$want" == GREEN ]]; then
    (( rc == 0 )) && pass "$id GREEN" || fail "$id want GREEN, rc=$rc: $(grep -E '^(FAIL|INSTRUMENT)' <<<"$out" | head -3 | tr '\n' '|')"
  elif (( rc >= 2 )); then fail "$id instrument failure rc=$rc: $(grep INSTRUMENT <<<"$out" | head -2 | tr '\n' '|')"
  else
    [[ -n "$why" ]] || { echo "[FATAL] row $id names no reason" >&2; exit 2; }
    (( rc == 1 )) && grep -F "FAIL[$want]" <<<"$out" | grep -qF -- "$why" && pass "$id caught by $want ($why)" \
      || fail "$id want FAIL[$want] naming '$why', rc=$rc: $(grep -E '^FAIL' <<<"$out" | head -3 | tr '\n' '|')"
  fi
}

# H8 -- control on the untouched base copy; anything but exit 0 with the full ledger aborts.
t="$SANDBOX/control"; cp -r "$BASE" "$t"; chmod -R u+w "$t"
ctl_out=$(bash "$SELF" --root "$t" 2>&1); ctl_rc=$?
if (( ctl_rc != 0 )) || ! grep -qxF "LEDGER $EXPECTED_LEDGER" <<<"$ctl_out"; then
  printf '[FATAL] H8 control on the base copy: rc=%s\n%s\n' "$ctl_rc" "$ctl_out" >&2; exit 2
fi
pass "H8 control exit 0 with the full ledger"

DRAIN_ARM='gh pr merge <N> --squash --auto --match-head-commit "${H:?run the arm check in this call}"'
OTHER_PIN_ARM='gh pr merge <N> --squash --auto --match-head-commit "${HEAD_X:?some other variable}"'
RM_ARM='bash "$SS_LIB" with_lock merge-main 600 -- \'
SS_LINE='SS_LIB="${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh"'
DQ_ARM='gh pr merge "$N" --squash --auto --match-head-commit "${H:?run the arm check in this call}"'
SHIP_ANCHOR='## Headless Mode Detection'
SETTLE_ANCHOR='## Operator-authorized variant'
SYNC_REARM='(3) re-arm once, only when autoMergeRequest is null, through the arm check ('
MQJ_DIE='arm it first through plugins/soleur/skills/review/references/review-evidence-comment.md#arm-check'

m1()   { edit "$1/$DRAIN" "$DRAIN_ARM" 'gh pr merge <N> --squash --auto'; }
m2()   { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$RM_ARM" "$RM_ARM"$'\n'"gh pr merge <number> --squash --auto && \\"; }
m2b()  { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --auto; gh pr merge 8 --auto --match-head-commit "${H:?x}"'; }
m3()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" "$DQ_ARM"$'\n''gh pr merge "$N" \'$'\n''  --squash --auto'; }
m5()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$LINK" 'review-evidence-comment.md'; }
m5b()  { edit_all "$1/$SETTLE" "$LINK" 'review-evidence-comment.md'; }
m6()   { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n'"$CANON_REFUSE"; }
m7()   { edit "$1/$CANON" "  $CANON_REFUSE"$'\n' ''; }
m7b()  { edit "$1/$CANON" "$CANON_ARM" '--match-head-commit "$H"'; }
m8a()  { rm -f "$1/plugins/soleur/skills/product-roadmap/SKILL.md"; }
m8b()  { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" 'gh pr merge "$N" --squash'; }
m10a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'H=$(gh pr view <number> --json headRefOid --jq .headRefOid)'$'\n'"$SS_LINE"; }
m10b() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'read -r PR H'$'\n'"$SS_LINE"; }
m10c() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" ': "${H:=x}"'$'\n'"$SS_LINE"; }
m10d() { edit_first "$1/$SETTLE" "   $SETTLE_TIE" '   H=$SHA'$'\n'"   $SETTLE_TIE"; }
m11a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" "$OTHER_PIN_ARM"$'\n'"$SS_LINE"; }
m15()  { edit "$1/$SYNC" "$SYNC_REARM" '(3) re-arm once: gh pr merge $PR --squash --auto ('; }
m16()  { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n''Read the head into `EXEMPT_HEAD` first.'; }
m16b() { edit "$1/$SETTLE" "$SETTLE_ANCHOR" 'Read `soleur-exempt-<N>.head` first.'$'\n\n'"$SETTLE_ANCHOR"; }
m16c() { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "When it is armed, do not re-arm." "drain-prs' exempt PRs re-arm through drain-prs §4 instead. When it is armed, do not re-arm."; }
m16d() { edit "$1/$CANON" $'\n## Arm check\n' $'\n'"DOMAIN_SURFACE_RE='(^|/)infra/'"$'\n\n## Arm check\n'; }
m19()  { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "     bash \"\$SS_LIB\" with_lock merge-main 600 -- \\"$'\n'"       gh pr merge <number> --squash --auto --match-head-commit \"\${H:?run the arm check in this call}\"" "     bash \"\$SS_LIB\" with_lock merge-main 600 -- \\"$'\n'"       gh pr merge <number> --squash --auto"; }
m19b() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "     echo \"SOLEUR_SESSION_STATE_UNAVAILABLE path=\$SS_LIB reason=running-unlocked\""$'\n'"     gh pr merge <number> --squash --auto --match-head-commit \"\${H:?run the arm check in this call}\"" "     echo \"SOLEUR_SESSION_STATE_UNAVAILABLE path=\$SS_LIB reason=running-unlocked\""$'\n'"     gh pr merge <number> --squash --auto"; }
m20()  { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge $(gh pr view --json number --jq .number) --squash --auto'; }
m20b() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --squash --auto # --match-head-commit "${H:?x}"'; }
m20c() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --squash --auto --match-head-commit "${H:?x}" --match-head-commit "$SHA"'; }
m21a() { edit_first "$1/$SETTLE" "   $SETTLE_TIE" '   :'; }
m21b() { python3 -I -c '
import sys
p, o = sys.argv[1], sys.argv[2]; s = open(p, encoding="utf-8").read(); i = s.find(o); j = s.find(o, i + 1)
if i < 0 or j < 0: sys.exit(1)
open(p, "w", encoding="utf-8").write(s[:j] + "true || {" + s[j + len(o):])' "$1/$SETTLE" "$SETTLE_TIE" || { echo "[FATAL] m21b did not land" >&2; exit 2; }; }
m21c() { edit_first "$1/$SETTLE" "   $SETTLE_PLACE" '   :'; }
m21d() { edit_first "$1/$SETTLE" "$SETTLE_TIE" '[ "${H:?run the arm check in this call}" != "$SHA" ] || {'; }
m21e() { edit_first "$1/$SETTLE" "$SETTLE_FETCH" 'git fetch -q origin "pull/<N>/head"; {'; }
m21f() { edit_first "$1/$SETTLE" "   $SETTLE_TIE_LINE" "   # $SETTLE_TIE_LINE"; }
m21g() { python3 -I -c '
import sys
p, o = sys.argv[1], sys.argv[2]; s = open(p, encoding="utf-8").read(); i = s.find(o); j = s.find(o, i + 1)
if i < 0 or j < 0: sys.exit(1)
open(p, "w", encoding="utf-8").write(s[:j] + o.replace("exit 4; }", "true; }") + s[j + len(o):])' "$1/$SETTLE" "$SETTLE_TIE_LINE" || { echo "[FATAL] m21g did not land" >&2; exit 2; }; }
m21h() { edit_first "$1/$SETTLE" "   $SETTLE_TIE_LINE" "   true || $SETTLE_TIE_LINE"; }
m21i() { edit_first "$1/$SETTLE" "   $SETTLE_TIE_LINE" "   echo '$SETTLE_TIE_LINE'"; }
m21j() { edit_first "$1/$SETTLE" "   $SETTLE_FETCH_LINE" "   ${SETTLE_FETCH_LINE/exit 1; \}/true; \}}"; }
m22a() { edit "$1/$CANON" '  && git merge-base --is-ancestor "$EV" "$H" \'$'\n' ''; }
m22b() { edit "$1/$CANON" '  && R=$(git rev-list --first-parent --no-merges "$EV..$H") && [ -z "$R" ] \'$'\n' ''; }
m22c() { edit "$1/$CANON" '|last // ""|' '|first // ""|'; }
m22d() { edit "$1/$CANON" ' and ([scan("coverage=")]|length==1) and ([scan("unresolved-P1-P2=")]|length==1)' ''; }
m22e() { edit "$1/$CANON" 'capture("^Review-Evidence: head=' 'capture("head='; }
m23()  { edit "$1/$MON" "only through $SETTLE_PATH" 'only through ship/references/settle-then-admin-merge.md'; }
m24a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'gh pr merge `echo <number>` --squash --auto && \'$'\n'"$SS_LINE"; }
m24b() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''```bash'$'\n''gh pr merge `echo 7` --squash --auto'$'\n''```'; }
m24c() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'gh pr merge $((7)) --squash --auto && \'$'\n'"$SS_LINE"; }
m24d() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge $((PR)) --squash --auto'; }
m24e() { edit "$1/$DRAIN" "$DRAIN_ARM" 'gh pr merge <N> --squash --auto $(echo --match-head-commit "${H:?run the arm check in this call}")'; }
m24f() { edit "$1/$DRAIN" "$DRAIN_ARM" 'gh pr merge <N> --squash --auto "$(echo --match-head-commit "${H:?run the arm check in this call}")"'; }
m16e() { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "When it is armed, do not re-arm." "Exempt PRs re-arm directly. When it is armed, do not re-arm."; }
m16f() { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "When it is armed, do not re-arm." "Bot PRs are exempt from the arm check. When it is armed, do not re-arm."; }
m17()  { edit "$1/$MQJ" "$MQJ_DIE" 'arm it first'; }
m18()  { edit "$1/$MQJ" "$MQJ_DIE" 'arm it: gh pr merge $PR --squash --auto'; }
h3() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --disable-auto'$'\n''gh pr merge "$N" --auto --squash --match-head-commit "${H:?x}"'; }
h4() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''Run `gh pr merge` unlocked, or `gh pr merge <N> --squash`.'; }
h5() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''See [the check](x/'"$LINK"').'$'\n\n''```bash'$'\n''# comment'$'\n''gh pr merge 9 --squash --auto --match-head-commit "${H:?x}"'$'\n''```'; }
h6() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge 7 --squash --auto --match-head-commit "${H:?x}"'; }
h8() { mkdir -p "$1/plugins/soleur/skills/community/scripts" && printf '%s\n' '# a non-exempt arm of the cap table' > "$1/plugins/soleur/skills/community/scripts/x.sh"; }
h9() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''```bash'$'\n''gh pr merge "$(echo 7)" --squash --auto --match-head-commit "${H:?x}" # see `x`'$'\n''```'; }
h7() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh api -H=Accept:application/json repos/{owner}/{repo}/pulls/7'; }

echo "== mutation rows"
row M1 A1 m1 'drain-prs/SKILL.md:'
row M2 A1 m2 'product-roadmap/SKILL.md:'
row M2b A1 m2b 'ship/SKILL.md:'
row M3 A1 m3 'merge-queue-dequeue.md:'
row M5 A2 m5 'merge-queue-dequeue.md does not link'
row M5b A2 m5b 'settle-then-admin-merge.md does not link'
row M6 A2b m6 'refusal statement files'
row M7 A3 m7 'refusal statement missing'
row M7b A3 m7b 'pinned arm line missing'
row M8a A1-floor m8a 'missing site file'
row M8b A1-floor m8b 'has no arm span'
row M10a A1-noH m10a 'H=$(gh pr view'
row M10b A1-noH m10b 'read -r PR H'
row M10c A1-noH m10c '${H:=x}'
row M10d A1-noH m10d 'H=$SHA'
row M11a A1 m11a 'HEAD_X'
row M15 A5 m15 'sync-pr-behind.sh:'
row M16 A6 m16 'EXEMPT_HEAD'
row M16b A6 m16b 'soleur-exempt-'
row M16c A6 m16c "exempt PRs"
row M16d A6 m16d 'DOMAIN_SURFACE_RE'
row M17 A5 m17 'not-armed message does not name'
row M18 A5 m18 'merge-queue-jump.sh:'
row M19 A1 m19 'product-roadmap/SKILL.md:'
row M19b A1 m19b 'product-roadmap/SKILL.md:'
row M20 A1 m20 'number --jq .number) --squash --auto'
row M20b A1 m20b 'without the'
row M20c A1 m20c '2 --match-head-commit flags'
row M21a A7 m21a 'BLOCK 1 missing: [ "${H:?'
row M21b A7 m21b 'BLOCK 2 missing: [ "${H:?'
row M21c A7 m21c 'BLOCK 1 missing: # REPLACE THIS LINE'
row M21d A7 m21d 'BLOCK 1 missing: [ "${H:?'
row M21e A7 m21e 'BLOCK 1 missing: git fetch'
row M21f A7 m21f 'BLOCK 1 missing: [ "${H:?'
row M21g A7 m21g 'BLOCK 2 missing: [ "${H:?'
row M21h A7 m21h 'BLOCK 1 missing: [ "${H:?'
row M21i A7 m21i 'BLOCK 1 missing: [ "${H:?'
row M21j A7 m21j 'BLOCK 1 missing: git fetch'
row M22a A3 m22a 'merge-base --is-ancestor'
row M22b A3 m22b 'rev-list --first-parent'
row M22c A3 m22c '|last // ""'
row M22d A3 m22d 'length==1'
row M22e A3 m22e '^Review-Evidence: head='
row M23 A5 m23 'monitor-pr-checks.sh not-armed line does not name plugins/soleur/skills/ship'
row M24a A1 m24a 'product-roadmap/SKILL.md:'
row M24b A1 m24b 'ship/SKILL.md:'
row M24c A1 m24c 'product-roadmap/SKILL.md:'
row M24d A1 m24d 'ship/SKILL.md:'
row M24e A1 m24e 'outside a substitution'
row M24f A1 m24f 'outside a substitution'
row M16e A6 m16e 'Exempt PRs'
row M16f A6 m16f 'exempt from the arm check'

echo "== harness rows (each must stay GREEN: a disarm, a prose mention, a fenced comment, a lock-wrapped pinned arm, gh api -H, non-exempt prose off-site, a fenced pinned arm with a substitution and a trailing comment)"
row H3 GREEN h3
row H4 GREEN h4
row H5 GREEN h5
row H6 GREEN h6
row H7 GREEN h7
row H8b GREEN h8
row H9 GREEN h9

MIN_CASES=59  # 52 mutation rows + 7 harness rows; raise it in the same edit that adds a row
echo
echo "passes=$passes fails=$fails cases=$CASES_RUN"
if (( CASES_RUN < MIN_CASES )); then printf '[FATAL] only %s rows ran (want >= %s)\n' "$CASES_RUN" "$MIN_CASES" >&2; exit 1; fi
if (( fails > 0 )); then printf 'FAILED: %s\n' "${FAILED[@]}" >&2; exit 1; fi
echo "arm-check-sites: all rows passed"
