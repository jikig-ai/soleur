#!/usr/bin/env bash
# Mutation battery for www-apex-canonicalizer.test.sh (ADR-194, #7640).
#
# WHY THIS FILE EXISTS. The guard asserts that the www→apex 301 chain is shaped correctly.
# It cannot tell you whether those assertions can FAIL. Reading a guard is not evidence it
# works — a guard whose predicate is unmatchable reports clean forever, and this repo has
# shipped exactly that several times (a `[^\n]` bracket expression that excludes the letter
# `n`, a bare-token grep satisfied by the comment written to explain the token, a `>= N`
# floor counting assertion CALLS rather than bodies).
#
# It exists as a FILE rather than as a one-time observation for a reason specific to this
# guard. `scripts/guard-vacuity-floor.test.sh` gives it no mutation coverage: the floor is an
# exact cardinality (`-ne`), which `floor_lines_of` does not classify as a floor candidate,
# and `apps/web-platform/infra/` sits in that meta-guard's DEFERRED_DIRS regardless. So this
# battery is the ONLY falsifiability evidence the guard has. Uncommitted, it would decay into
# a claim in a commit message — which is the position this repo exists to reject.
#
# IT HAS ALREADY EARNED ITS KEEP. Two defects in the guard were found by RUNNING this matrix,
# not by reading the guard:
#
#   * a version-pinned `npx wrangler@4 pages deploy` was invisible to the invocation
#     detector, so a pinned publish read as "no publish yet" and BOTH cross-file coupling
#     cases passed by asserting an absence that was not there. Found by the row that injects
#     a CORRECT pinned invocation: it was RED, for a reason that was not its mutation.
#   * scoring on the exit code alone credited M7a for an incidental failure. Requiring each
#     row to name ITS OWN case is what exposed the above.
#
# CONTRACT. Baseline first: the guard must be GREEN on an unmutated sandbox, or the run
# ABORTS — a red baseline makes every row below red for a reason that is not its mutation.
# Then per row: copy the pristine sandbox, apply ONE mutation, confirm it actually LANDED
# (`diff -rq` against the pristine tree — a mutator whose anchor stopped matching is a case
# that tested NOTHING and reports the baseline, which is indistinguishable from a pass), run
# the guard, and require the named case among the failures.
#
# GREEN ROWS ARE ROWS. Four rows must leave the guard at exit 0. Three of them are the
# stage-machinery controls: without a row proving the guard is green on a POST-CUTOVER tree,
# every post-cutover assertion could be structurally red and the rows that mutate them would
# be killed for free. The fourth is the Guard Contract's H2 — a guard that rejects everything
# is as broken as one that accepts everything.
#
# HARNESS FAILURES ABORT (exit 2), never degrade. A battery that cannot copy its own tree
# does not produce a missing result, it produces a CONFIDENT WRONG one: the next case runs
# against the previous case's mutation and reports a verdict about the SUT that the harness's
# own breakage produced.

set -uo pipefail

# /tmp is a machine-global RAM-backed tmpfs shared by every parallel worktree on this box.
# run-registered-suites.sh and test-all.sh both default TMPDIR=/var/tmp; a DIRECT invocation
# (the inner loop while editing the guard) does not, so without this line the verdicts become
# a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
GUARD="www-apex-canonicalizer.test.sh"
INFRA_REL="apps/web-platform/infra"

PASS=0
FAIL=0
TOTAL=0

die() { printf 'HARNESS ABORT: %s\n' "$*" >&2; exit 2; }

WORK="$(mktemp -d -t wac-mutation-XXXXXX)" || die "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

# THE SANDBOX MUST CARRY EVERYTHING THE GUARD RESOLVES, INCLUDING WHAT IT REACHES OUTSIDE ITS
# OWN DIRECTORY. The guard cross-reads two files two levels up, and relocating a script
# silently breaks every `$SCRIPT_DIR/../..`-relative read — a failure indistinguishable from a
# real one. Derived from the guard, not remembered:
#   $ grep -nE 'REPO_ROOT|SCRIPT_DIR' www-apex-canonicalizer.test.sh
# The baseline check below is what turns a missed entry into a HARNESS ABORT instead of
# sixteen confident-wrong verdicts.
SANDBOX="$WORK/pristine"
GUARD_REL="$INFRA_REL/$GUARD"
DNS_REL="$INFRA_REL/dns.tf"
PAGES_REL="$INFRA_REL/cf-pages.tf"
REDIR_REL="$INFRA_REL/seo-bulk-redirects.tf"
WF_REL=".github/workflows/deploy-docs.yml"
CNAME_REL="plugins/soleur/docs/CNAME"
NEEDED=("$GUARD_REL" "$DNS_REL" "$PAGES_REL" "$REDIR_REL" "$WF_REL" "$CNAME_REL")

for rel in "${NEEDED[@]}"; do
  mkdir -p "$SANDBOX/$(dirname "$rel")" || die "could not create sandbox dir for $rel"
  [[ -f "$REPO_ROOT/$rel" ]] || die "source file missing from the repo: $rel"
  cp -a "$REPO_ROOT/$rel" "$SANDBOX/$rel" || die "could not copy $rel into the sandbox"
done
chmod +x "$SANDBOX/$GUARD_REL" || die "could not make the sandboxed guard executable"

# ---------------------------------------------------------------------------------------
# THE MUTATORS
#
# python rather than sed because most rows are BLOCK relocations or multi-line edits, and
# because python lets each row ASSERT its anchor was found instead of silently no-opping (a
# sed `s///` that matches nothing exits 0 and prints success). Every function raises on a
# missing anchor, which the caller turns into a HARNESS ABORT rather than a verdict.
# ---------------------------------------------------------------------------------------
MUT="$WORK/mutators.py"
cat > "$MUT" <<'PYEOF'
import os, re, sys

DNS   = "apps/web-platform/infra/dns.tf"
PAGES = "apps/web-platform/infra/cf-pages.tf"
REDIR = "apps/web-platform/infra/seo-bulk-redirects.tf"
GUARD = "apps/web-platform/infra/www-apex-canonicalizer.test.sh"
WF    = ".github/workflows/deploy-docs.yml"

ROOT = sys.argv[2]
def path(rel): return os.path.join(ROOT, rel)
def rd(rel):   return open(path(rel)).read()
def wr(rel, t): open(path(rel), "w").write(t)

def close_brace(text, i):
    """i indexes the '{' that opens a block; return the index just past its match."""
    d = 0
    while i < len(text):
        if text[i] == "{": d += 1
        elif text[i] == "}":
            d -= 1
            if d == 0: return i + 1
        i += 1
    raise AssertionError("unbalanced braces")

def res_span(text, typ, name):
    m = re.search(r'^resource\s+"%s"\s+"%s"\s*\{' % (typ, name), text, re.M)
    assert m, "resource %s.%s not found" % (typ, name)
    return m.start(), close_brace(text, m.end() - 1)

def sub_spans(text, s, e, kw):
    out = []
    for m in re.finditer(r"^\s*%s\s*\{" % kw, text[s:e], re.M):
        out.append((s + m.start(), s + close_brace(text[s:e], m.end() - 1)))
    return out

# --- the post-cutover (PR3) dns.tf shape, used by the stage control and by M4 ------------
PAGES_APEX = '''resource "cloudflare_record" "pages_apex" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "soleur-docs.pages.dev"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www" {
  zone_id = var.cf_zone_id
  name    = "www"
  content = "192.0.2.1"
  type    = "A"
  proxied = true
  ttl     = 1
}
'''

def cutover():
    """Replace the GitHub-Pages substrate with the Pages substrate PR3 will land."""
    t = rd(DNS)
    s, e = res_span(t, "cloudflare_record", "github_pages")
    ws, we = res_span(t, "cloudflare_record", "www")
    lo, hi = min(s, ws), max(e, we)
    wr(DNS, t[:lo] + PAGES_APEX + t[hi:])

WRANGLER_STEP = """
      - name: Publish to Cloudflare Pages
        run: npx %s pages deploy _site --project-name %s --branch %s
"""

def inject_wrangler(pin, proj, branch):
    t = rd(WF)
    wr(WF, t.rstrip("\n") + "\n" + WRANGLER_STEP % (pin, proj, branch))

# --- M1: delete the www item, leaving the list declared ----------------------------------
def m1():
    t = rd(REDIR)
    s, e = res_span(t, "cloudflare_list", "www_canonical")
    items = sub_spans(t, s, e, "item")
    assert len(items) == 1, "expected exactly one item block, found %d" % len(items)
    a, b = items[0]
    wr(REDIR, t[:a] + "\n" + t[b:])

# --- M2: remove the SECOND rules block — the chokepoint. The list survives and is inert --
def m2():
    t = rd(REDIR)
    s, e = res_span(t, "cloudflare_ruleset", "bulk_redirects")
    r = sub_spans(t, s, e, "rules")
    assert len(r) == 2, "expected two rules blocks, found %d" % len(r)
    a, b = r[1]
    wr(REDIR, t[:a] + "\n" + t[b:])

# --- M3: reorder so the www rule precedes the legal rule ---------------------------------
def m3():
    t = rd(REDIR)
    s, e = res_span(t, "cloudflare_ruleset", "bulk_redirects")
    r = sub_spans(t, s, e, "rules")
    assert len(r) == 2, "expected two rules blocks, found %d" % len(r)
    (a1, b1), (a2, b2) = r
    wr(REDIR, t[:a1] + t[a2:b2] + t[b1:a2] + t[a1:b1] + t[b2:])

# --- M4: repoint the apex off the Pages project (post-cutover tree) ----------------------
def m4():
    cutover()
    t = rd(DNS)
    old = 'content = "soleur-docs.pages.dev"'
    assert old in t, "cutover apex content anchor not found"
    wr(DNS, t.replace(old, 'content = "jikig-ai.github.io"'))

# --- M4b: repoint AND RETYPE. A guard deriving its stage from the apex record's own type
#     would re-derive to `github-pages` here and score its own mutation as correct. -------
def m4b():
    cutover()
    t = rd(DNS)
    old = '''  content = "soleur-docs.pages.dev"
  type    = "CNAME"'''
    assert old in t, "cutover apex content/type pair not found"
    wr(DNS, t.replace(old, '''  content = "185.199.108.153"
  type    = "A"'''))

# --- M5: drop the proxied mandate on either record ---------------------------------------
def _unproxy(resname):
    t = rd(DNS)
    s, e = res_span(t, "cloudflare_record", resname)
    body = t[s:e]
    assert "proxied = true" in body, "%s carries no proxied = true" % resname
    wr(DNS, t[:s] + body.replace("proxied = true", "proxied = false") + t[e:])

def m5a(): _unproxy("github_pages")
def m5b(): _unproxy("www")

# --- M6: a SECOND redirect list bound by a THIRD rule, M1/M2 left intact -----------------
def m6():
    t = rd(REDIR)
    ls, le = res_span(t, "cloudflare_list", "www_canonical")
    dup = t[ls:le].replace("www_canonical", "www_canonical_v2")
    rs, re_ = res_span(t, "cloudflare_ruleset", "bulk_redirects")
    r = sub_spans(t, rs, re_, "rules")
    assert len(r) == 2, "expected two rules blocks, found %d" % len(r)
    third = t[r[1][0]:r[1][1]].replace("www_canonical", "www_canonical_v2")
    t = t[:r[1][1]] + "\n" + third + t[r[1][1]:] + "\n" + dup + "\n"
    wr(REDIR, t)

# --- M7: the cross-file couplings diverge ------------------------------------------------
def m7a(): inject_wrangler("wrangler@4", "soleur-docs", "gh-pages")
def m7b(): inject_wrangler("wrangler@4", "soleur-docs-preview", "main")

# --- M8: replace the guard's assertion list with an empty list ---------------------------
def m8():
    t = rd(GUARD)
    a = t.index("# LINK 1")
    a = t.rindex("# ---", 0, a)
    b = t.index("# ANTI-VACUITY FLOOR AND ACCOUNTING")
    b = t.rindex("# ---", 0, b)
    wr(GUARD, t[:a] + t[b:])

# --- H1: delete the case M2 targets, from the SUITE rather than the substrate ------------
def h1():
    t = rd(GUARD)
    a = t.index("eq_case 'legal_redirects,www_canonical'")
    b = t.index("\n", t.index("(first-match-wins)\"", a)) + 1
    wr(GUARD, t[:a] + t[b:])

# --- Green rows --------------------------------------------------------------------------
def g_stage():   cutover()
def g_pinned():  inject_wrangler("wrangler@4", "soleur-docs", "main")
def g_unpinned():inject_wrangler("wrangler", "soleur-docs", "main")

def h2():
    """Non-canonical but semantically identical: different internal whitespace, unrelated
    list items reordered, and the dns.tf contract comment reflowed. The guard asserts
    content anchors, not byte-equality with a canonical file."""
    t = rd(REDIR)
    t = re.sub(r"^(\s*)([a-z_]+)\s*=\s*",
               lambda m: "%s  %s   =    " % (m.group(1), m.group(2)), t, flags=re.M)
    s, e = res_span(t, "cloudflare_list", "legal_redirects")
    body = t[s:e]
    spans = [(m.start(), close_brace(body, m.end() - 1))
             for m in re.finditer(r"^\s*item\s*\{", body, re.M)]
    assert len(spans) > 1, "legal_redirects should carry several items to reorder"
    # Rebuild the item region with the items REVERSED and the original separators kept in
    # place. Concatenating the item bodies alone would also delete whatever sits between
    # them, which is a second, unrelated mutation riding along inside a must-ACCEPT row.
    texts = [body[a:b] for a, b in spans]
    seps = [body[spans[i][1]:spans[i + 1][0]] for i in range(len(spans) - 1)]
    region = ""
    for i, txt in enumerate(reversed(texts)):
        region += txt
        if i < len(seps): region += seps[i]
    t = t[:s] + body[:spans[0][0]] + region + body[spans[-1][1]:] + t[e:]
    t = t.replace("\nresource ", "\n\nresource ")
    wr(REDIR, t)
    t = rd(DNS)
    old = "# GitHub Pages -- docs site (soleur.ai apex + www redirect)"
    assert old in t, "dns.tf contract comment anchor not found"
    wr(DNS, t.replace(old, "#\n#   GitHub Pages -- docs site\n#   (soleur.ai apex + the www redirect)\n#"))

ROWS = {
    "M1": m1, "M2": m2, "M3": m3, "M4": m4, "M4b": m4b, "M5a": m5a, "M5b": m5b,
    "M6": m6, "M7a": m7a, "M7b": m7b, "M8": m8, "H1": h1,
    "G-stage": g_stage, "G-pinned": g_pinned, "G-unpinned": g_unpinned, "H2": h2,
}

row = sys.argv[1]
assert row in ROWS, "unknown row %s" % row
ROWS[row]()
PYEOF
[[ -s "$MUT" ]] || die "could not write the mutator module"

# Runs the guard inside a sandbox tree. Echoes the exit code; writes the log to $2.
run_guard() {
  local root="$1" log="$2"
  ( cd "$root/$INFRA_REL" && bash "./$GUARD" ) > "$log" 2>&1
  echo $?
}

# --- Baseline: the guard must be GREEN on an unmutated sandbox ---------------------------
# Without this every row below could be reporting a reason unrelated to its mutation, and a
# sandbox missing one of the cross-read files would look exactly like a real regression.
BASE_LOG="$WORK/baseline.log"
BASE_RC="$(run_guard "$SANDBOX" "$BASE_LOG")"
if [[ "$BASE_RC" != "0" ]]; then
  printf 'HARNESS ABORT: the guard is not green on an UNMUTATED sandbox (rc=%s).\n' "$BASE_RC" >&2
  printf 'Every mutation row below would report RED for a reason that is not its mutation.\n' >&2
  grep -E '^  FAIL|^\[FATAL\]' "$BASE_LOG" >&2 | head -20
  exit 2
fi
printf '=== www-apex-canonicalizer mutation battery (#7640) ===\n'
printf 'baseline: guard GREEN on unmutated sandbox (%s)\n\n' "$(grep -oE 'OK: [0-9]+/[0-9]+' "$BASE_LOG")"

# case_row <id> <kill|green> <expected-failing-case-substring> <note>
#
# `kill` rows must exit non-zero AND name their own case. Scoping the match to FAILURE lines
# is load-bearing: the guard echoes each case description on PASS as well as FAIL, so an
# unscoped grep matches the PASS line of the very case the row claims went RED.
case_row() {
  local id="$1" mode="$2" expect="$3" note="$4"
  TOTAL=$((TOTAL + 1))

  local dir="$WORK/case-$id"
  rm -rf "$dir" || die "case $id: could not clear the case dir"
  cp -a "$SANDBOX" "$dir" || die "case $id: could not copy the pristine sandbox"

  python3 "$MUT" "$id" "$dir" \
    || die "case $id: the mutator failed to apply (its anchor was not found) — this case tested NOTHING"
  if diff -rq "$SANDBOX" "$dir" >/dev/null 2>&1; then
    die "case $id: the mutation did not change the tree — this case tested NOTHING and would report the baseline"
  fi

  local log="$WORK/case-$id.log" rc
  rc="$(run_guard "$dir" "$log")"

  if [[ "$mode" == "green" ]]; then
    if [[ "$rc" != "0" ]]; then
      FAIL=$((FAIL + 1))
      printf '  BROKEN:   %-10s the guard went RED (rc=%s) on a change it must ACCEPT — %s\n' "$id" "$rc" "$note"
      grep -E '^  FAIL|^\[FATAL\]' "$log" | head -5 | sed 's/^/              /'
      return
    fi
    PASS=$((PASS + 1))
    printf '  ACCEPTED: %-10s stayed GREEN — %s\n' "$id" "$note"
    return
  fi

  if [[ "$rc" == "0" ]]; then
    FAIL=$((FAIL + 1))
    printf '  SURVIVED: %-10s the guard stayed GREEN under this mutation.\n' "$id"
    printf '            Two readings, and one of them must be recorded before this ships:\n'
    printf '            (a) the guard does not exercise the property — fix the GUARD;\n'
    printf '            (b) the mutant is EQUIVALENT — prove no verdict changes, and say so here.\n'
    return
  fi
  # `grep -qF -- "$expect"`: the END-OF-OPTIONS marker is load-bearing, not decoration. Two
  # of the rows below expect a case naming `--branch` / `--project-name`, and without `--`
  # grep parses the expectation as an option, exits 2, and the row reports MISROUTED against
  # a guard that named its case correctly. Measured on the first run of this file.
  if ! grep -E '^  FAIL|^\[FATAL\]' "$log" | grep -qF -- "$expect"; then
    FAIL=$((FAIL + 1))
    printf '  MISROUTED: %-9s the guard went RED, but NOT on the case this row targets.\n' "$id"
    printf '             expected a failure naming: %s\n' "$expect"
    printf '             actual failures:\n'
    grep -E '^  FAIL|^\[FATAL\]' "$log" | head -5 | sed 's/^/               /'
    return
  fi
  PASS=$((PASS + 1))
  printf '  KILLED:   %-10s RED on "%s"\n' "$id" "$expect"
}

# --- Green rows first: they establish that the rows below can be killed for the right
#     reason. Without G-stage, every post-cutover assertion could be structurally red and
#     M4/M4b would be killed for free.
case_row G-stage    green ""  "post-cutover dns.tf (the PR3 shape) is accepted"
case_row G-pinned   green ""  "a correct VERSION-PINNED wrangler publish is accepted"
case_row G-unpinned green ""  "a correct unpinned wrangler publish is accepted"
case_row H2         green ""  "Guard Contract H2: non-canonical whitespace/ordering/comment reflow"

# --- Link 1: the redirect declaration
case_row M1  kill "source_url" ""

# --- Link 2: the binding chokepoint and its order. M2 is the row that matters most: the
#     declaration survives and nothing binds it, so the live 301 dies with every other
#     assertion green.
case_row M2  kill "first-match-wins" ""
case_row M3  kill "first-match-wins" ""
case_row M6  kill "exactly two rules" ""

# --- Link 3: the DNS substrate
case_row M4  kill "apex origin matches" ""
case_row M4b kill "apex origin matches" ""
case_row M5a kill "apex origin record is proxied" ""
case_row M5b kill "www record is proxied" ""

# --- Links 4/5: the cross-file couplings. The plan's highest-ranked risk — every in-file
#     assertion stays green while the custom domain serves a stale build.
case_row M7a kill "--branch equals cf-pages.tf production_branch" ""
case_row M7b kill "--project-name equals" ""

# --- The guard's own dispatch: M8 empties the assertion list, H1 deletes one case.
case_row M8  kill "vacuity floor" ""
case_row H1  kill "vacuity floor" ""

# ---------------------------------------------------------------------------------------
# An exact row cardinality, reported directly and NOT through this battery's own PASS/FAIL
# accounting: a battery whose rows were deleted prints `0/0 mutants killed` and exits 0,
# which is the vacuity class this file exists to close, one level up. Bump it deliberately
# when you add a row.
# ---------------------------------------------------------------------------------------
EXPECTED_ROWS=16
if [[ "$TOTAL" -ne "$EXPECTED_ROWS" ]]; then
  printf '[FATAL] battery cardinality: %d rows executed, expected exactly %d — a row was deleted, skipped, or added without updating EXPECTED_ROWS\n' \
    "$TOTAL" "$EXPECTED_ROWS" >&2
  exit 2
fi

printf '\n=== Results: %d/%d rows correct ===\n' "$PASS" "$TOTAL"
if (( FAIL > 0 )); then
  printf 'FAIL: %d row(s) survived, misrouted, or broke a must-accept row — the guard does not pin what it claims.\n' "$FAIL"
  exit 1
fi
printf 'OK\n'
