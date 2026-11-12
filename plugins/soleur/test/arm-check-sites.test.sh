#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Guard 1 of #12656 (plan: knowledge-base/project/plans/2026-11-12-fix-arm-check-drain-prs-product-roadmap-plan.md,
# `## Guard Contract`). Every skill site that arms or re-arms auto-merge, and sync-pr-behind's dequeue message, binds
# each arm to the head the Review-Evidence arm check set: `--match-head-commit "${H:?...}"`. Only the canonical
# statement in review-evidence-comment.md `## Arm check` sets H. The one exception is drain-prs' exempt arm, pinned to
# the head its read call wrote (`${EXEMPT_HEAD:?...}`). The exemption's path regex exists once, at column 0 of the
# canonical file, and every top-level alternative in it is load-bearing against the fixtures below.
#
# Two modes:
#   bash arm-check-sites.test.sh              driver: real-tree verdict, then the H8 control, mutation and harness rows
#   bash arm-check-sites.test.sh --root <dir> one assertion run over <dir>; prints FAIL[<id>] lines and a LEDGER line
# --root exit: 0 = ledger is exactly the nine IDs and nothing failed; 1 = an assertion failed or ZERO-SPANS;
#              2 = the instrument broke (python error, missing ledger ID). A row counts as caught only on exit 1
#              naming its expected ID; exit 2 or higher is an instrument failure, never a pass.
# SPAN_RE overrides the `gh pr merge` token pattern (H1 sets it to a pattern that matches nothing).
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SITES=(
  plugins/soleur/skills/ship/SKILL.md
  plugins/soleur/skills/merge-pr/SKILL.md
  plugins/soleur/skills/drain-prs/SKILL.md
  plugins/soleur/skills/product-roadmap/SKILL.md
  plugins/soleur/skills/ship/references/merge-queue-dequeue.md
)
DRAIN=plugins/soleur/skills/drain-prs/SKILL.md
CANON=plugins/soleur/skills/review/references/review-evidence-comment.md
SYNC=plugins/soleur/scripts/sync-pr-behind.sh
LINK='review-evidence-comment.md#arm-check'
EXPECTED_LEDGER='A1 A1-exempt A1-floor A1-noH A2 A2b A3 A4 A5'
# A1-noH: no site file assigns H. The `-` in the first class keeps `gh api -H=...` quiet (H7).
NOH_RE='(^|[^A-Za-z0-9_-])H(\+?=|\[[^]]*\]=)|\$\{H:?=|(read|declare|typeset|export|local|readonly|mapfile|readarray|for)([[:space:]]+[^;&|]*)?[[:space:]]H([[:space:]=;]|$)|printf[[:space:]]+-v[[:space:]]*H'
CANON_REFUSE='|| { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }'
CANON_ARM='--match-head-commit "${H:?run the arm check in this call}"'
MUST_MATCH=(
  apps/web-platform/infra/x.tf .github/workflows/a.yml supabase/migrations/1.sql docs/legal/terms.md
  apps/web-platform/lib/auth/x.ts apps/web-platform/package.json apps/web-platform/package-lock.json bun.lock
  Dockerfile .env.example apps/web-platform/middleware.ts a.tfvars .terraform.lock.hcl Cargo.lock
  .claude/settings.json AGENTS.rules.md plugins/soleur/hooks/x.sh plugins/soleur/skills/drain-prs/SKILL.md
  plugins/soleur/skills/review/references/review-evidence-comment.md scripts/test-all.sh .gitmodules infra/main.yml
  main.tf x.hcl db/migrations/x.rb db/seed.sql .github/CODEOWNERS lib/auth/x.yml config/secrets.yml x/doppler.yaml
  bun.lockb ops/cloud-init.yml CLAUDE.md plugins/soleur/hooks/x.yml .claude-plugin/plugin.yml scripts/x.yml
  bunfig.toml vitest.config.ts
)
# Real exempt bot PR paths (a community digest, the campaign calendar, a weakness digest, a legal-generate NOTICE).
MUST_NOT_MATCH=(
  knowledge-base/support/community/2026-11-12-digest.md knowledge-base/marketing/campaign-calendar.md
  knowledge-base/project/weakness-digest.md plugins/soleur/skills/legal-generate/NOTICE
)

# scan <root> <relpath>... : one `ARM<TAB>rel<TAB>line<TAB>span` line per arm span; exit 3 on a python error.
scan() {
  local root="$1"; shift
  python3 -I - "$root" "$@" <<'PY'
import os, re, sys
root, rels = sys.argv[1], sys.argv[2:]
tok = re.compile(os.environ.get("SPAN_RE") or r"(?<![A-Za-z0-9_-])gh\s+pr\s+merge(?![A-Za-z0-9_-])")
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

# run_root <root> : the assertion run. Prints FAIL[<id>] lines, ZERO-SPANS, and `LEDGER <ids>`; returns 0/1/2.
run_root() {
  local root="$1" f=0 out rel n c re p canon_hits ledger=()
  local -A per_file=() exempt_per=()
  out=$(scan "$root" "${SITES[@]}") || { echo "INSTRUMENT scanner (python) failed"; return 2; }

  # A1 -- every arm span carries the H pin; the EXEMPT_HEAD pin only in drain-prs.
  ledger+=(A1)
  while IFS=$'\t' read -r kind rel n s; do
    [[ "$kind" == ARM ]] || continue
    per_file[$rel]=$(( ${per_file[$rel]:-0} + 1 ))
    if [[ "$s" == *'--match-head-commit "${EXEMPT_HEAD:?'* ]]; then
      exempt_per[$rel]=$(( ${exempt_per[$rel]:-0} + 1 ))
      [[ "$rel" == "$DRAIN" ]] || { echo "FAIL[A1] $rel:$n exempt pin outside drain-prs: $s"; f=1; }
    elif [[ "$s" != *'--match-head-commit "${H:?'* ]]; then
      echo "FAIL[A1] $rel:$n arm without --match-head-commit \"\${H:?: $s"; f=1
    fi
  done <<<"$out"
  local total=0; for rel in "${!per_file[@]}"; do total=$(( total + per_file[$rel] )); done
  (( total > 0 )) || { echo "ZERO-SPANS the scanner found no arm span in any site"; f=1; }

  # A1-floor -- set identity: every site present, each with at least one arm span.
  ledger+=(A1-floor)
  for rel in "${SITES[@]}"; do
    if grep -q "^MISSING	$rel\$" <<<"$out"; then echo "FAIL[A1-floor] missing site file: $rel"; f=1
    elif (( ${per_file[$rel]:-0} < 1 )); then echo "FAIL[A1-floor] $rel has no arm span"; f=1; fi
  done

  # A1-noH -- only the canonical statement sets H.
  ledger+=(A1-noH)
  for rel in "${SITES[@]}"; do
    [[ -f "$root/$rel" ]] || continue
    c=$(grep -nE -- "$NOH_RE" "$root/$rel"); rc=$?
    (( rc <= 1 )) || { echo "INSTRUMENT grep failed on A1-noH ($rel)"; return 2; }
    [[ -z "$c" ]] || { while IFS= read -r l; do echo "FAIL[A1-noH] $rel:$l"; done <<<"$c"; f=1; }
  done

  # A1-exempt -- exactly one exempt arm, in drain-prs.
  ledger+=(A1-exempt)
  for rel in "${SITES[@]}"; do
    c=${exempt_per[$rel]:-0}
    if [[ "$rel" == "$DRAIN" ]]; then
      (( c == 1 )) || { echo "FAIL[A1-exempt] $rel has $c exempt arm spans (want exactly 1)"; f=1; }
    else
      (( c == 0 )) || { echo "FAIL[A1-exempt] $rel has $c exempt arm spans (want 0)"; f=1; }
    fi
  done

  # A2 -- every site links the canonical check.
  ledger+=(A2)
  for rel in "${SITES[@]}"; do
    [[ -f "$root/$rel" ]] || continue
    grep -qF -- "$LINK" "$root/$rel" || { echo "FAIL[A2] $rel does not link $LINK"; f=1; }
  done

  # A2b -- the refusal statement exists once, in the canonical file.
  ledger+=(A2b)
  canon_hits=$(cd "$root" && grep -rlF 'echo "ARM_CHECK refused:' plugins/soleur/skills/ 2>/dev/null)
  [[ "$canon_hits" == "$CANON" ]] || { echo "FAIL[A2b] refusal statement files: [$(tr '\n' ' ' <<<"$canon_hits")] (want only $CANON)"; f=1; }

  # A3 -- the canonical file carries the statement, the pinned arm and one column-0 regex line.
  ledger+=(A3)
  if [[ ! -f "$root/$CANON" ]]; then echo "FAIL[A3] canonical file missing: $CANON"; f=1
  else
    grep -qF -- "$CANON_REFUSE" "$root/$CANON" || { echo "FAIL[A3] canonical refusal statement missing"; f=1; }
    grep -qF -- "$CANON_ARM" "$root/$CANON" || { echo "FAIL[A3] canonical pinned arm line missing"; f=1; }
    c=$(grep -cE "^DOMAIN_SURFACE_RE='" "$root/$CANON")
    [[ "$c" == 1 ]] || { echo "FAIL[A3] canonical has $c column-0 DOMAIN_SURFACE_RE lines (want 1)"; f=1; }
  fi

  # A4 -- the domain regex: single copy, extracted the way drain-prs extracts it, and its behaviour.
  ledger+=(A4)
  canon_hits=$(cd "$root" && grep -rlE "^DOMAIN_SURFACE_RE='" plugins/soleur/skills/ 2>/dev/null)
  [[ "$canon_hits" == "$CANON" ]] || { echo "FAIL[A4] DOMAIN_SURFACE_RE files: [$(tr '\n' ' ' <<<"$canon_hits")] (want only $CANON)"; f=1; }
  re=$(sed -n "s/^DOMAIN_SURFACE_RE='\(.*\)'\$/\1/p" "$root/$CANON" 2>/dev/null | head -1)
  if [[ -z "$re" ]]; then echo "FAIL[A4] DOMAIN_SURFACE_RE not extracted from $CANON"; f=1
  else
    for p in "${MUST_MATCH[@]}"; do
      printf '%s\n' "$p" | grep -qE -- "$re"; rc=$?
      (( rc <= 1 )) || { echo "INSTRUMENT grep -E failed on the extracted regex"; return 2; }
      (( rc == 0 )) || { echo "FAIL[A4] MUST-MATCH path not matched: $p"; f=1; }
    done
    for p in "${MUST_NOT_MATCH[@]}"; do
      printf '%s\n' "$p" | grep -qE -- "$re" && { echo "FAIL[A4] MUST-NOT-MATCH path matched: $p"; f=1; }
    done
  fi

  # A5 -- sync-pr-behind.sh has no arm span, and its dequeued message routes the re-arm through the check.
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

# One read-only base copy of the seven files; each row gets its own writable copy.
BASE="$SANDBOX/base"
for rel in "${SITES[@]}" "$CANON" "$SYNC"; do
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

# row <id> <want: GREEN | ZERO-SPANS | assertion id> <fn|-> [env assignment]
row() {
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1" want="$2" fn="$3" envset="${4-}" t out rc
  t="$SANDBOX/row-$id"; rm -rf "$t"; cp -r "$BASE" "$t" && chmod -R u+w "$t" || { echo "[FATAL] row copy $id" >&2; exit 2; }
  [[ "$fn" == - ]] || "$fn" "$t"
  if [[ -n "$envset" ]]; then out=$(env "$envset" bash "$SELF" --root "$t" 2>&1); rc=$?
  else out=$(bash "$SELF" --root "$t" 2>&1); rc=$?; fi
  if [[ "$want" == GREEN ]]; then
    (( rc == 0 )) && pass "$id GREEN" || fail "$id want GREEN, rc=$rc: $(grep -E '^(FAIL|INSTRUMENT|ZERO)' <<<"$out" | head -3 | tr '\n' '|')"
  elif (( rc >= 2 )); then fail "$id instrument failure rc=$rc: $(grep INSTRUMENT <<<"$out" | head -2 | tr '\n' '|')"
  elif [[ "$want" == ZERO-SPANS ]]; then
    (( rc == 1 )) && grep -q '^ZERO-SPANS' <<<"$out" && pass "$id ZERO-SPANS" || fail "$id want ZERO-SPANS, rc=$rc"
  else
    (( rc == 1 )) && grep -qF "FAIL[$want]" <<<"$out" && pass "$id caught by $want" \
      || fail "$id want FAIL[$want], rc=$rc: $(grep -E '^(FAIL|ZERO)' <<<"$out" | head -3 | tr '\n' '|')"
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
SHIP_ANCHOR='## Arm check'

m1()   { edit "$1/$DRAIN" "$DRAIN_ARM" 'gh pr merge <N> --squash --auto'; }
m2()   { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$RM_ARM" "$RM_ARM"$'\n'"gh pr merge <number> --squash --auto && \\"; }
m2b()  { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --auto; gh pr merge 8 --auto --match-head-commit "${H:?x}"'; }
m3()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" "$DQ_ARM"$'\n''gh pr merge "$N" \'$'\n''  --squash --auto'; }
m5()   { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$LINK" 'review-evidence-comment.md'; }
m6()   { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n'"$CANON_REFUSE"; }
m7()   { edit "$1/$CANON" "  $CANON_REFUSE"$'\n' ''; }
m8a()  { rm -f "$1/plugins/soleur/skills/product-roadmap/SKILL.md"; }
m8b()  { edit "$1/plugins/soleur/skills/ship/references/merge-queue-dequeue.md" "$DQ_ARM" 'gh pr merge "$N" --squash'; }
m10a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'H=$(gh pr view <number> --json headRefOid --jq .headRefOid)'$'\n'"$SS_LINE"; }
m10b() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" 'read -r PR H'$'\n'"$SS_LINE"; }
m10c() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" ': "${H:=x}"'$'\n'"$SS_LINE"; }
m11a() { edit "$1/plugins/soleur/skills/product-roadmap/SKILL.md" "$SS_LINE" "$EXEMPT_ARM"$'\n'"$SS_LINE"; }
m11b() { edit "$1/$DRAIN" "$EXEMPT_ARM" "$EXEMPT_ARM"$'\n'"$EXEMPT_ARM"; }
m14p() { edit "$1/$DRAIN" "$DRAIN_ARM" "$DRAIN_ARM"$'\n'"$(grep -E "^DOMAIN_SURFACE_RE='" "$BASE/$CANON")"; }
m15()  { python3 -I - "$1/$SYNC" <<'PY' || { echo "[FATAL] m15 did not land" >&2; exit 2; }
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
new, n = re.subn(r"\(3\) re-arm once[^.]*\.", "(3) re-arm once: gh pr merge $PR --squash --auto.", s, count=1)
if n != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(new)
PY
}
h3() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh pr merge 7 --disable-auto'$'\n''gh pr merge "$N" --auto --squash --match-head-commit "${H:?x}"'; }
h4() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''Run `gh pr merge` unlocked, or `gh pr merge <N> --squash`.'; }
h5() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''See [the check](x/'"$LINK"').'$'\n\n''```bash'$'\n''# comment'$'\n''gh pr merge 9 --squash --auto --match-head-commit "${H:?x}"'$'\n''```'; }
h6() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge 7 --squash --auto --match-head-commit "${H:?x}"'; }
h7() { edit "$1/plugins/soleur/skills/ship/SKILL.md" "$SHIP_ANCHOR" "$SHIP_ANCHOR"$'\n\n''gh api -H=Accept:application/json repos/{owner}/{repo}/pulls/7'; }

echo "== mutation rows"
row M1 A1 m1
row M2 A1 m2
row M2b A1 m2b
row M3 A1 m3
row M5 A2 m5
row M6 A2b m6
row M7 A3 m7
row M8a A1-floor m8a
row M8b A1-floor m8b
row M10a A1-noH m10a
row M10b A1-noH m10b
row M10c A1-noH m10c
row M11a A1-exempt m11a
row M11b A1-exempt m11b
row M14-paste A4 m14p
row M15 A5 m15

# M14 loop -- delete each top-level alternative of the canonical regex alone; a MUST-MATCH fixture must miss.
RE_LINE=$(grep -E "^DOMAIN_SURFACE_RE='" "$BASE/$CANON")
mapfile -t ALTS < <(RE_LINE="$RE_LINE" python3 -I -c '
import os
r = os.environ["RE_LINE"].split("=", 1)[1][1:-1]
out, d, b, cur = [], 0, False, ""
i = 0
while i < len(r):
    c = r[i]
    if c == "\\" and i + 1 < len(r):
        cur += r[i:i+2]; i += 2; continue
    if b:
        if c == "]": b = False
    elif c == "[": b = True
    elif c == "(": d += 1
    elif c == ")": d -= 1
    elif c == "|" and d == 0:
        out.append(cur); cur = ""; i += 1; continue
    cur += c; i += 1
out.append(cur)
print("\n".join(out))')
(( ${#ALTS[@]} >= 20 )) || { printf '[FATAL] M14: split found only %s alternatives\n' "${#ALTS[@]}" >&2; exit 2; }
m14_alt() { edit "$1/$CANON" "$RE_LINE" "$M14_NEW"; }
for k in "${!ALTS[@]}"; do
  rest=(); for j in "${!ALTS[@]}"; do (( j == k )) || rest+=("${ALTS[$j]}"); done
  M14_NEW="DOMAIN_SURFACE_RE='$(IFS='|'; printf '%s' "${rest[*]}")'"
  row "M14-alt$k" A4 m14_alt
done

echo "== harness rows"
row H1 ZERO-SPANS - 'SPAN_RE=(?!)'
row H3 GREEN h3
row H4 GREEN h4
row H5 GREEN h5
row H6 GREEN h6
row H7 GREEN h7

MIN_CASES=$(( 16 + ${#ALTS[@]} + 6 ))
echo
echo "passes=$passes fails=$fails cases=$CASES_RUN alternatives=${#ALTS[@]}"
if (( CASES_RUN < MIN_CASES )); then printf '[FATAL] only %s rows ran (want >= %s)\n' "$CASES_RUN" "$MIN_CASES" >&2; exit 1; fi
if (( fails > 0 )); then printf 'FAILED: %s\n' "${FAILED[@]}" >&2; exit 1; fi
echo "arm-check-sites: all rows passed"
