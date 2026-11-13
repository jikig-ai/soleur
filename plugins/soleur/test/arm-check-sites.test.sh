#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC1003  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose; a trailing backslash inside single quotes is a literal continuation marker
# Guard 1 of #12656 (plan: knowledge-base/project/plans/2026-11-12-fix-arm-check-drain-prs-product-roadmap-plan.md,
# `## Guard Contract`). Every skill site that arms or re-arms auto-merge, and sync-pr-behind's dequeue message, binds
# each arm to the head the Review-Evidence arm check set: `--match-head-commit "${H:?...}"`. Only the canonical
# statement in review-evidence-comment.md `## Arm check` sets H. There is no exempt arm: drain-prs' bot exemption was
# deleted (CTO ruling R1, 2026-11-13), and A6 keeps its tokens from coming back. The admin-merge hatch links the check
# (A2), and the two scripts that print re-arm instructions route them through it without an arm of their own (A5).
#
# Two modes:
#   bash arm-check-sites.test.sh              driver: real-tree verdict, then the H8 control, mutation and harness rows
#   bash arm-check-sites.test.sh --root <dir> one assertion run over <dir>; prints FAIL[<id>] lines and a LEDGER line
# --root exit: 0 = ledger is exactly EXPECTED_LEDGER and nothing failed; 1 = an assertion failed;
#              2 = the instrument broke (python error, missing ledger ID). A row counts as caught only on exit 1
#              naming its expected ID and reason; exit 2 or higher is an instrument failure, never a pass.
# A scanner that finds no span at all is caught by A1-floor (every site needs one), so there is no separate zero check.
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
SETTLE=plugins/soleur/skills/ship/references/settle-then-admin-merge.md
DRAIN=plugins/soleur/skills/drain-prs/SKILL.md
CANON=plugins/soleur/skills/review/references/review-evidence-comment.md
SYNC=plugins/soleur/scripts/sync-pr-behind.sh
MQJ=scripts/merge-queue-jump.sh
LINK='review-evidence-comment.md#arm-check'
EXPECTED_LEDGER='A1 A1-floor A1-noH A2 A2b A3 A5 A6'
# A1-noH: no site file assigns H. The `-` in the first class keeps `gh api -H=...` quiet (H7).
NOH_RE='(^|[^A-Za-z0-9_-])H(\+?=|\[[^]]*\]=)|\$\{H:?=|(read|declare|typeset|export|local|readonly|mapfile|readarray|for)([[:space:]]+[^;&|]*)?[[:space:]]H([[:space:]=;]|$)|printf[[:space:]]+-v[[:space:]]*H'
CANON_REFUSE='|| { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }'
CANON_ARM='--match-head-commit "${H:?run the arm check in this call}"'

# scan <root> <relpath>... : one `ARM<TAB>rel<TAB>line<TAB>span` line per arm span; exit 3 on a python error.
scan() {
  local root="$1"; shift
  python3 -I - "$root" "$@" <<'PY'
import os, re, sys
root, rels = sys.argv[1], sys.argv[2:]
tok = re.compile(r"(?<![A-Za-z0-9_-])gh\s+pr\s+merge(?![A-Za-z0-9_-])")
auto = re.compile(r"(?<![A-Za-z0-9_-])--auto(?![A-Za-z0-9_-])")
def joined(text):
    out, buf, start = [], "", None
    for n, line in enumerate(text.split("\n"), 1):
        if start is None:
            start = n
        m = re.search(r"\\[ \t]*$", line)
        if m:
            buf += line[:m.start()] + " "
            continue
        out.append((start, buf + line)); buf, start = "", None
    if start is not None:
        out.append((start, buf))
    return out
def span(line, i, nxt):
    # from the token to the first unquoted ; && || | ) or an unescaped backtick (any quote state),
    # the next token, or the end of the joined line. Quote state starts unquoted at the token.
    q, j = None, i
    while j < nxt:
        c = line[j]
        if c == "`" and (j == 0 or line[j - 1] != "\\"):
            break
        if q:
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c in ";|)" or line.startswith("&&", j):
            break
        j += 1
    return line[i:j]
for rel in rels:
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        print("MISSING\t" + rel); continue
    with open(p, encoding="utf-8") as fh:
        text = fh.read()
    for n, line in joined(text):
        hits = [m.start() for m in tok.finditer(line)]
        for k, i in enumerate(hits):
            s = span(line, i, hits[k + 1] if k + 1 < len(hits) else len(line))
            if auto.search(s):
                print("ARM\t%s\t%d\t%s" % (rel, n, s.replace("\t", " ")))
PY
  local rc=$?; (( rc == 0 )) || return 3
}

# run_root <root> : the assertion run. Prints FAIL[<id>] lines and `LEDGER <ids>`; returns 0/1/2.
run_root() {
  local root="$1" f=0 out rel n c canon_hits ledger=()
  local -A per_file=()
  out=$(scan "$root" "${SITES[@]}") || { echo "INSTRUMENT scanner (python) failed"; return 2; }

  # A1 -- every arm span carries the H pin.
  ledger+=(A1)
  while IFS=$'\t' read -r kind rel n s; do
    [[ "$kind" == ARM ]] || continue
    per_file[$rel]=$(( ${per_file[$rel]:-0} + 1 ))
    [[ "$s" == *'--match-head-commit "${H:?'* ]] || { echo "FAIL[A1] $rel:$n arm without --match-head-commit \"\${H:?: $s"; f=1; }
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
  canon_hits=$(cd "$root" && grep -rlF 'echo "ARM_CHECK refused:' plugins/soleur/skills/ 2>/dev/null)
  [[ "$canon_hits" == "$CANON" ]] || { echo "FAIL[A2b] refusal statement files: [$(tr '\n' ' ' <<<"$canon_hits")] (want only $CANON)"; f=1; }

  # A3 -- the canonical file carries the refusal statement and the pinned arm line.
  ledger+=(A3)
  if [[ ! -f "$root/$CANON" ]]; then echo "FAIL[A3] canonical file missing: $CANON"; f=1
  else
    grep -qF -- "$CANON_REFUSE" "$root/$CANON" || { echo "FAIL[A3] canonical refusal statement missing"; f=1; }
    grep -qF -- "$CANON_ARM" "$root/$CANON" || { echo "FAIL[A3] canonical pinned arm line missing"; f=1; }
  fi

  # A5 -- neither script that prints re-arm instructions has an arm span, and each message names the check.
  ledger+=(A5)
  if [[ ! -f "$root/$SYNC" ]]; then echo "FAIL[A5] missing $SYNC"; f=1
  else
    c=$(scan "$root" "$SYNC") || { echo "INSTRUMENT scanner (python) failed on $SYNC"; return 2; }
    [[ -z "$c" ]] || { while IFS=$'\t' read -r _ rel n s; do echo "FAIL[A5] $rel:$n arm span: $s"; done <<<"$c"; f=1; }
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
    [[ -z "$c" ]] || { while IFS=$'\t' read -r _ rel n s; do echo "FAIL[A5] $rel:$n arm span: $s"; done <<<"$c"; f=1; }
    c=$(grep -E '^[[:space:]]*die "PR #\$PR is not in the merge queue and has no auto-merge armed' "$root/$MQJ")
    if [[ -z "$c" ]]; then echo "FAIL[A5] no not-armed die line in $MQJ"; f=1
    else [[ "$c" == *"$LINK"* ]] || { echo "FAIL[A5] $MQJ not-armed message does not name $LINK"; f=1; }; fi
  fi

  # A6 -- tombstone: the deleted exempt arm's tokens appear nowhere under plugins/soleur/skills/.
  ledger+=(A6)
  c=$(cd "$root" && grep -rnE 'EXEMPT_HEAD|soleur-exempt-' plugins/soleur/skills/ 2>/dev/null); rc=$?
  (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A6"; return 2; }
  [[ -z "$c" ]] || { while IFS= read -r l; do echo "FAIL[A6] exempt-arm token: $l"; done <<<"$c"; f=1; }

  echo "LEDGER $(printf '%s\n' "${ledger[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  [[ "$(printf '%s\n' "${ledger[@]}" | sort | tr '\n' ' ' | sed 's/ $//')" == "$EXPECTED_LEDGER" ]] \
    || { echo "INSTRUMENT ledger is not exactly: $EXPECTED_LEDGER"; return 2; }
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
for rel in "${SITES[@]}" "${LINK_ONLY[@]}" "$CANON" "$SYNC" "$MQJ"; do
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
EXEMPT_ARM='gh pr merge <N> --squash --auto --match-head-commit "${EXEMPT_HEAD:?run the exempt read call first}"'
RM_ARM='bash "$SS_LIB" with_lock merge-main 600 -- \'
SS_LINE='SS_LIB="${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh"'
DQ_ARM='gh pr merge "$N" --squash --auto --match-head-commit "${H:?run the arm check in this call}"'
SHIP_ANCHOR='## Headless Mode Detection'
SETTLE_TIE='   [ "$H" = "$SHA" ]'
SETTLE_ANCHOR='## Operator-authorized variant'
SYNC_REARM='(3) re-arm once, only when autoMergeRequest is null, through the arm check ('
MQJ_DIE='arm it first through plugins/soleur/skills/review/references/review-evidence-comment.md#arm-check'

m1()   { edit "$1/$DRAIN" "$DRAIN_ARM" 'gh pr merge <N> --squash --auto'; }
m2()   { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$RM_ARM" "$RM_ARM"$'\n'"gh pr merge <number> --squash --auto && \\"; }
m2b()  { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --auto; gh pr merge 8 --auto --match-head-commit "${H:?x}"'; }
m3()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" "$DQ_ARM"$'\n''gh pr merge "$N" \'$'\n''  --squash --auto'; }
m5()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$LINK" 'review-evidence-comment.md'; }
m5b()  { while grep -qF -- "$LINK" "$1/$SETTLE"; do edit_first "$1/$SETTLE" "$LINK" 'review-evidence-comment.md'; done; }
m6()   { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n'"$CANON_REFUSE"; }
m7()   { edit "$1/$CANON" "  $CANON_REFUSE"$'\n' ''; }
m7b()  { edit "$1/$CANON" "$CANON_ARM" '--match-head-commit "$H"'; }
m8a()  { rm -f "$1/plugins/soleur/skills/product-roadmap/SKILL.md"; }
m8b()  { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" 'gh pr merge "$N" --squash'; }
m10a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'H=$(gh pr view <number> --json headRefOid --jq .headRefOid)'$'\n'"$SS_LINE"; }
m10b() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'read -r PR H'$'\n'"$SS_LINE"; }
m10c() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" ': "${H:=x}"'$'\n'"$SS_LINE"; }
m10d() { edit_first "$1/$SETTLE" "$SETTLE_TIE" '   H=$SHA'$'\n'"$SETTLE_TIE"; }
m11a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" "$EXEMPT_ARM"$'\n'"$SS_LINE"; }
m15()  { edit "$1/$SYNC" "$SYNC_REARM" '(3) re-arm once: gh pr merge $PR --squash --auto ('; }
m16()  { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n''Read the head into `EXEMPT_HEAD` first.'; }
m16b() { edit "$1/$SETTLE" "$SETTLE_ANCHOR" 'Read `soleur-exempt-<N>.head` first.'$'\n\n'"$SETTLE_ANCHOR"; }
m17()  { edit "$1/$MQJ" "$MQJ_DIE" 'arm it first'; }
m18()  { edit "$1/$MQJ" "$MQJ_DIE" 'arm it: gh pr merge $PR --squash --auto'; }
h3() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --disable-auto'$'\n''gh pr merge "$N" --auto --squash --match-head-commit "${H:?x}"'; }
h4() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''Run `gh pr merge` unlocked, or `gh pr merge <N> --squash`.'; }
h5() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''See [the check](x/'"$LINK"').'$'\n\n''```bash'$'\n''# comment'$'\n''gh pr merge 9 --squash --auto --match-head-commit "${H:?x}"'$'\n''```'; }
h6() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge 7 --squash --auto --match-head-commit "${H:?x}"'; }
h7() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh api -H=Accept:application/json repos/{owner}/{repo}/pulls/7'; }

echo "== mutation rows"
row M1 A1 m1 'arm without'
row M2 A1 m2 'arm without'
row M2b A1 m2b 'arm without'
row M3 A1 m3 'arm without'
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
row M11a A1 m11a 'EXEMPT_HEAD'
row M15 A5 m15 'arm span'
row M16 A6 m16 'EXEMPT_HEAD'
row M16b A6 m16b 'soleur-exempt-'
row M17 A5 m17 'not-armed message does not name'
row M18 A5 m18 'arm span'

echo "== harness rows (each must stay GREEN: a disarm, a prose mention, a fenced comment, a lock-wrapped pinned arm, gh api -H)"
row H3 GREEN h3
row H4 GREEN h4
row H5 GREEN h5
row H6 GREEN h6
row H7 GREEN h7

MIN_CASES=26  # 21 mutation rows + 5 harness rows; raise it in the same edit that adds a row
echo
echo "passes=$passes fails=$fails cases=$CASES_RUN"
if (( CASES_RUN < MIN_CASES )); then printf '[FATAL] only %s rows ran (want >= %s)\n' "$CASES_RUN" "$MIN_CASES" >&2; exit 1; fi
if (( fails > 0 )); then printf 'FAILED: %s\n' "${FAILED[@]}" >&2; exit 1; fi
echo "arm-check-sites: all rows passed"
