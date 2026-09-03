#!/usr/bin/env bash
# Mutation battery for ssl-full-mitigation.test.sh (#7749, ADR-194).
#
# WHY THIS FILE EXISTS. The guard asserts that the `ssl = "full"` config rule holding
# soleur.ai up is present and unshadowed. It cannot tell you whether those assertions
# can FAIL, and a guard on a control this load-bearing that has not been shown to fail
# is not a guard. Reading it is not evidence: this repo has repeatedly shipped guards
# whose predicate was unmatchable and which therefore reported clean forever.
#
# The guard is also a config-file assertion, which is precisely the class that rots into
# vacuity — so the rows below deliberately attack three different axes rather than N
# variations of one:
#
#   SUT      — the substrate the guard reads (the rule's fields, its ordering on BOTH
#              sides of the mitigation, its absence)
#   FIXTURE  — the stage (a post-cutover dns.tf must be ACCEPTED, not merely not-crashed)
#   DISPATCH — the guard's own verdict helpers and floor
#
# The dispatch rows matter most and are the ones an implementation-only battery misses:
# every SUT mutation is observed THROUGH pass()/fail(), so nothing that perturbs the rule
# can detect those helpers going silent.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
GUARD="ssl-full-mitigation.test.sh"
INFRA_REL="apps/web-platform/infra"

PASS=0
FAIL=0
TOTAL=0

die() { printf 'HARNESS ABORT: %s\n' "$*" >&2; exit 2; }

WORK="$(mktemp -d -t sslfull-mutation-XXXXXX)" || die "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

# The sandbox must carry everything the guard resolves. Derived from the guard, not
# remembered:  grep -nE 'SCRIPT_DIR/' ssl-full-mitigation.test.sh
SANDBOX="$WORK/pristine"
GUARD_REL="$INFRA_REL/$GUARD"
CONF_REL="$INFRA_REL/seo-config-rules.tf"
DNS_REL="$INFRA_REL/dns.tf"
NEEDED=("$GUARD_REL" "$CONF_REL" "$DNS_REL")

for rel in "${NEEDED[@]}"; do
  mkdir -p "$SANDBOX/$(dirname "$rel")" || die "could not create sandbox dir for $rel"
  [[ -f "$REPO_ROOT/$rel" ]] || die "source file missing from the repo: $rel"
  cp -a "$REPO_ROOT/$rel" "$SANDBOX/$rel" || die "could not copy $rel into the sandbox"
done
chmod +x "$SANDBOX/$GUARD_REL" || die "could not make the sandboxed guard executable"

MUT="$WORK/mutators.py"
cat > "$MUT" <<'PYEOF'
import re, sys, pathlib, shutil

def rd(p):
    return pathlib.Path(p).read_text()

def wr(p, s):
    pathlib.Path(p).write_text(s)

def sub_once(path, old, new):
    """Replace exactly one occurrence, asserting the anchor is unique.

    A non-unique anchor is how a mutation silently edits a COMMENT three lines
    above the real code and reports the baseline as a survivor."""
    s = rd(path)
    n = s.count(old)
    assert n == 1, "anchor occurs %d times (want exactly 1): %r" % (n, old[:60])
    wr(path, s.replace(old, new, 1))

CONF = "apps/web-platform/infra/seo-config-rules.tf"
DNS  = "apps/web-platform/infra/dns.tf"
GRD  = "apps/web-platform/infra/ssl-full-mitigation.test.sh"

# The mitigation rules block, verbatim. Anchored on the ssl value so it cannot match
# the email_obfuscation rule that shares its expression.
BLOCK_RE = re.compile(
    r'\n  rules \{\n'
    r'    action      = "set_config"\n'
    r'    description = "TEMPORARY[^"]*"\n'
    r'    enabled     = true\n'
    r'    expression  = "\(http\.host in \{\\"soleur\.ai\\" \\"www\.soleur\.ai\\"\}\)"\n'
    r'    action_parameters \{\n'
    r'      ssl = "full"\n'
    r'    \}\n'
    r'  \}\n'
)

def m1_disabled(root):
    """enabled = true -> false, on the mitigation rule only."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    wr(p, s[:m.start()] + m.group(0).replace("enabled     = true", "enabled     = false") + s[m.end():])

def m2_strict(root):
    """ssl = "full" -> "strict" (re-validates the expired cert => 526)."""
    sub_once("%s/%s" % (root, CONF), 'ssl = "full"', 'ssl = "strict"')

def m2b_flexible(root):
    """ssl = "full" -> "flexible" (cleartext to origin: different, worse failure)."""
    sub_once("%s/%s" % (root, CONF), 'ssl = "full"', 'ssl = "flexible"')

def m3_drop_www(root):
    """Drop www.soleur.ai from the mitigation's host set."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    mutated = m.group(0).replace(
        r'"(http.host in {\"soleur.ai\" \"www.soleur.ai\"})"',
        r'"(http.host eq \"soleur.ai\")"')
    assert mutated != m.group(0), "host-set anchor not found inside the block"
    wr(p, s[:m.start()] + mutated + s[m.end():])

def m4_delete_block(root):
    """Delete the whole mitigation rules block — the cleanup-PR scenario."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    wr(p, s[:m.start()] + "\n" + s[m.end():])

SHADOW = (
    '\n  rules {\n'
    '    action      = "set_config"\n'
    '    description = "tighten TLS posture"\n'
    '    enabled     = true\n'
    '    expression  = "(http.host in {\\"soleur.ai\\" \\"www.soleur.ai\\"})"\n'
    '    action_parameters {\n'
    '      ssl = "strict"\n'
    '    }\n'
    '  }\n'
)

def m5_shadow_below(root):
    """Insert a competing ssl rule BELOW the mitigation — the DANGEROUS position.

    `set_config` is non-terminating, so Cloudflare applies the LAST matching rule in
    the phase: this overwrites the mitigation while the mitigation block is still
    present and still reads "full". The site is down and the file looks correct.

    An earlier revision of this row inserted ABOVE and described that as the dangerous
    case. That was backwards — caught in review against Cloudflare's ruleset-engine
    docs. M5b covers the above position separately."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    wr(p, s[:m.start()] + m.group(0) + SHADOW + s[m.end():])

def m5b_shadow_above(root):
    """Insert a competing ssl rule ABOVE the mitigation.

    Harmless for the EFFECTIVE value (the mitigation below overwrites it), but the
    guard must still refuse it: two rules setting ssl for these hosts means the
    outcome depends on declaration order, so a later reorder silently breaks the site.
    Asserting cardinality rather than position is what makes both directions fail."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    wr(p, s[:m.start()] + SHADOW + m.group(0) + s[m.end():])

def g_postcutover(root):
    """Post-cutover substrate: dns.tf loses the Pages origin, mitigation removed.

    MUST be ACCEPTED. Without this row the guard could be 'always red unless the
    rule is present', which would block the cutover it is supposed to survive."""
    p = "%s/%s" % (root, DNS)
    s = rd(p)
    for ip in ("185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"):
        s = s.replace('"%s"' % ip, '"192.0.2.1"')
    s = s.replace('"jikig-ai.github.io"', '"soleur-ai.pages.dev"')
    # A real cutover also retires the GitHub-Pages-specific record resource; the apex
    # becomes a Pages custom domain. Leaving the block named `github_pages` behind is
    # not a post-cutover tree, and the guard is right to keep requiring the rule then.
    s = s.replace('resource "cloudflare_record" "github_pages"',
                  'resource "cloudflare_record" "pages_apex"')
    wr(p, s)
    m4_delete_block(root)

def g_comment_reflow(root):
    """Reflow the rationale comments. MUST be ACCEPTED — the guard reads stripped text."""
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    s = s.replace("# REMOVAL CONDITION", "# REMOVAL  CONDITION\n  #   (reflowed by a docs pass)")
    wr(p, s)

def h1_neuter_fail(root):
    """fail() stops counting. The accounting check must catch it."""
    sub_once("%s/%s" % (root, GRD),
             "fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\\n' \"$1\"; }",
             "fail() { printf '  FAIL: %s\\n' \"$1\"; }")

def h2_neuter_both(root):
    """Both verdict helpers become no-ops: the classic 0 passed / 0 failed / exit 0."""
    p = "%s/%s" % (root, GRD)
    s = rd(p)
    s = s.replace("pass() { PASS=$((PASS + 1)); printf '  PASS: %s\\n' \"$1\"; }", "pass() { :; }")
    s = s.replace("fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\\n' \"$1\"; }", "fail() { :; }")
    wr(p, s)

def h3_drop_a_case(root):
    """Delete one assertion case. The exact-cardinality floor must catch it."""
    sub_once("%s/%s" % (root, GRD),
             """    rc=1; printf '%s' "$m_expr" | grep -qF 'www.soleur.ai' && rc=0
    verdict "$rc" "the mitigation expression covers www.soleur.ai\"""",
             "")

def _insert_below(root, block):
    p = "%s/%s" % (root, CONF)
    s = rd(p)
    m = BLOCK_RE.search(s)
    assert m, "mitigation block not found"
    wr(p, s[:m.start()] + m.group(0) + block + s[m.end():])

def _rule(expr, ssl='"strict"'):
    return ('\n  rules {\n'
            '    action      = "set_config"\n'
            '    description = "tighten TLS posture"\n'
            '    enabled     = true\n'
            '    expression  = "%s"\n'
            '    action_parameters {\n'
            '      ssl = %s\n'
            '    }\n'
            '  }\n' % (expr, ssl))

def m6_shadow_negated_host(root):
    """A rule that MATCHES the apex without naming it.

    `(http.host ne \"app.soleur.ai\")` matches soleur.ai and www.soleur.ai. A count
    keyed on host literals does not see it; it still overwrites the mitigation."""
    _insert_below(root, _rule('(http.host ne \\"app.soleur.ai\\")'))

def m7_shadow_tautology(root):
    """`(true)` matches everything, including the apex."""
    _insert_below(root, _rule('(true)'))

def m8_shadow_with_equals(root):
    """A shadow whose expression contains '=' — defeats a greedy RHS split.

    The extractor used to capture from the LAST '=' on the line, truncating this
    expression to garbage so the rule was not counted."""
    _insert_below(root, _rule(
        '(http.host in {\\"soleur.ai\\" \\"www.soleur.ai\\"} and http.request.uri.query ne \\"debug=1\\")'))

def m9_resource_count(root):
    """`count = 0` destroys every rule in the ruleset, mitigation included."""
    sub_once("%s/%s" % (root, CONF),
             'resource "cloudflare_ruleset" "seo_config_settings" {',
             'resource "cloudflare_ruleset" "seo_config_settings" {\n  count = var.enable_seo_config ? 1 : 0')

def m10_lifecycle_ignore(root):
    """`ignore_changes = [rules]` stops Terraform reconciling a dashboard deletion."""
    sub_once("%s/%s" % (root, CONF),
             'resource "cloudflare_ruleset" "seo_config_settings" {',
             'resource "cloudflare_ruleset" "seo_config_settings" {\n  lifecycle {\n    ignore_changes = [rules]\n  }')

def m11_phase(root):
    """A different phase means the ruleset does not govern these requests."""
    sub_once("%s/%s" % (root, CONF), 'phase       = "http_config_settings"', 'phase       = "http_request_late_transform"')

def s1_records_moved(root):
    """Records moved to a sibling .tf. MUST stay pre-cutover.

    Reading dns.tf alone made this a silent self-retirement of the guard."""
    import shutil
    src = "%s/%s" % (root, DNS)
    dst = "%s/apps/web-platform/infra/dns-records.tf" % root
    shutil.move(src, dst)
    pathlib.Path(src).write_text('# records relocated to dns-records.tf\n')

def s2_ips_parameterized(root):
    """IP literals replaced by a variable. MUST stay pre-cutover (record block remains)."""
    p = "%s/%s" % (root, DNS)
    s = rd(p)
    for ip in ("185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"):
        s = s.replace('"%s"' % ip, "var.pages_ip")
    s = s.replace('"jikig-ai.github.io"', "var.pages_cname")
    wr(p, s)

ROWS = {
    "M1": m1_disabled, "M2": m2_strict, "M2b": m2b_flexible, "M3": m3_drop_www,
    "M4": m4_delete_block, "M5": m5_shadow_below, "M5b": m5b_shadow_above,
    "G-post": g_postcutover, "G-reflow": g_comment_reflow,
    "H1": h1_neuter_fail, "H2": h2_neuter_both, "H3": h3_drop_a_case,
    "M6": m6_shadow_negated_host, "M7": m7_shadow_tautology, "M8": m8_shadow_with_equals,
    "M9": m9_resource_count, "M10": m10_lifecycle_ignore, "M11": m11_phase,
    "S1": s1_records_moved, "S2": s2_ips_parameterized,
}

row, root = sys.argv[1], sys.argv[2]
assert row in ROWS, "unknown row %s" % row
ROWS[row](root)
PYEOF
[[ -s "$MUT" ]] || die "could not write the mutator module"

run_guard() {
  local root="$1" log="$2"
  ( cd "$root/$INFRA_REL" && bash "./$GUARD" ) > "$log" 2>&1
  echo $?
}

# --- Baseline: GREEN on an unmutated sandbox ---------------------------------------------
# A red baseline voids every row below — each would report a reason unrelated to its
# mutation, and a sandbox missing a cross-read file looks exactly like a real regression.
BASE_LOG="$WORK/baseline.log"
BASE_RC="$(run_guard "$SANDBOX" "$BASE_LOG")"
if [[ "$BASE_RC" != "0" ]]; then
  printf 'HARNESS ABORT: the guard is not green on an UNMUTATED sandbox (rc=%s).\n' "$BASE_RC" >&2
  grep -E '^  FAIL|^\[FATAL\]' "$BASE_LOG" >&2 | head -20
  exit 2
fi
printf '=== ssl=full mitigation mutation battery (#7749) ===\n'
printf 'baseline: guard GREEN on unmutated sandbox (%s)\n\n' "$(grep -oE 'OK: [0-9]+/[0-9]+' "$BASE_LOG")"

# case_row <id> <kill|green> <expected-failing-line-substring> <note>
#
# Scoping the match to FAILURE lines is load-bearing: the guard prints each case
# description on PASS as well as FAIL, so an unscoped grep matches the PASS line of the
# very case the row claims went RED.
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
      printf '  BROKEN:   %-9s the guard went RED (rc=%s) on a change it must ACCEPT — %s\n' "$id" "$rc" "$note"
      grep -E '^  FAIL|^\[FATAL\]' "$log" | head -5 | sed 's/^/              /'
      return
    fi
    PASS=$((PASS + 1))
    printf '  ACCEPTED: %-9s stayed GREEN — %s\n' "$id" "$note"
    return
  fi

  if [[ "$rc" == "0" ]]; then
    FAIL=$((FAIL + 1))
    printf '  SURVIVED: %-9s the guard stayed GREEN under this mutation.\n' "$id"
    printf '            Two readings, one of which must be recorded before this ships:\n'
    printf '            (a) the guard does not exercise the property — fix the GUARD;\n'
    printf '            (b) the mutant is EQUIVALENT — prove no verdict changes, and say so here.\n'
    return
  fi
  if ! grep -E '^  FAIL|^\[FATAL\]' "$log" | grep -qF -- "$expect"; then
    FAIL=$((FAIL + 1))
    printf '  MISROUTED: %-8s the guard went RED, but NOT on the case this row targets.\n' "$id"
    printf '             expected a failure naming: %s\n' "$expect"
    grep -E '^  FAIL|^\[FATAL\]' "$log" | head -5 | sed 's/^/               /'
    return
  fi
  PASS=$((PASS + 1))
  printf '  KILLED:   %-9s RED on "%s"\n' "$id" "$expect"
}

# --- GREEN rows first: they establish the kill rows below can fail for the RIGHT reason.
#     Without G-post, a guard that is simply "always red" would kill every M row for free.
case_row G-post   green "" "post-cutover dns.tf with the mitigation removed is ACCEPTED (removal exit 1)"
case_row G-reflow green "" "comment reflow around the rule is ACCEPTED (assertions read stripped text)"

# --- SUT axis: the rule's own fields, its ordering, and its absence
case_row M1  kill "enabled = true"          ""
case_row M2  kill "ssl = full"              ""
case_row M2b kill "ssl = full"              ""
case_row M3  kill "covers www.soleur.ai"    ""
case_row M4  kill "is present"              ""
case_row M5  kill "exactly one rule"       ""
case_row M5b kill "exactly one rule"       ""

# --- Shadow rules that MATCH the apex without SPELLING it, and one that defeats a
#     greedy RHS split. Each was a measured survivor before the count was re-keyed on
#     the presence of an ssl key rather than on host literals.
case_row M6  kill "exactly one rule"       ""
case_row M7  kill "exactly one rule"       ""
case_row M8  kill "exactly one rule"       ""

# --- RESOURCE-level destruction paths. None of these touch the rule block, so no
#     mutation of the rule could ever have surfaced them.
case_row M9  kill "count/for_each"         ""
case_row M10 kill "lifecycle block"        ""
case_row M11 kill "phase is http_config_settings" ""

# --- STAGE fail-open. Both are ordinary refactors with no intent to touch SSL, and
#     both silently retired the guard when it read dns.tf alone. They must remain
#     pre-cutover, i.e. the guard must still REQUIRE the rule; the rule is present in
#     these sandboxes, so the expected outcome is GREEN, and the row proves the stage
#     did not flip by also deleting nothing.
case_row S1  green "" "records moved to a sibling .tf still resolve as pre-cutover"
case_row S2  green "" "parameterized IP/CNAME literals still resolve as pre-cutover"

# --- DISPATCH axis: the guard's own accounting. Unreachable from any SUT mutation.
case_row H1  kill "verdict helpers are not counting" ""
case_row H2  kill "verdict helpers are not counting" ""
case_row H3  kill "vacuity floor"           ""

printf '\n'
if [[ "$FAIL" -ne 0 ]]; then
  printf 'FAILED: %d/%d rows behaved as specified\n' "$PASS" "$TOTAL"
  exit 1
fi
printf 'OK: %d/%d rows behaved as specified\n' "$PASS" "$TOTAL"
