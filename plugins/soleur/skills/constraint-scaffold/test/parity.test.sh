#!/usr/bin/env bash
# Template <-> emission parity for the constraint-scaffold L1 gate (ADR-071).
#
# The dependency-cruiser config and the shared runner are emitted as
# BYTE-IDENTICAL copies of the skill's templates; the CI workflow is a single
# `sed __TARGET_DIR__ -> apps/web-platform` substitution of the workflow
# template; and the repo-root dogfood gate lives folded as the `constraint-gates*`
# member steps of `jobs.quality-advisory` inside
# `.github/workflows/pr-quality-guards.yml` (#8902, member-folded under #12089) — structurally compared to the template job. ANY edit to a template
# MUST be mirrored into every emitted copy (and vice-versa), or the gate Soleur
# ships diverges from the gate Soleur tests. This test fails loud on any drift.
#
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Accumulate-then-exit; diff
# command-substitutions are guarded with `|| true` so `set -e` does not abort
# before fail() prints.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
REF="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/references"
APP="$REPO_ROOT/apps/web-platform"
TARGET_DIR="apps/web-platform"

passes=0
fails=0
# The INDEPENDENT row counter (ADR-193 #2). Incremented at every CALL SITE, never inside
# pass()/fail() — the VERDICT helpers touch only the verdict counters — so a stubbed fail() drops
# a verdict without dropping its count and the conservation check below notices. Top level only,
# never inside a `$( … )`.
cases=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
# Instrument self-test — DIRECTION, not only presence (a fail() misrouted to `passes` keeps the
# conservation check and the floor green). Reported via printf >&2 + exit 1, never through the
# helper it checks (ADR-193).
fail "instrument self-test (expected — proves fail() records a FAILURE)" >/dev/null
pass "instrument self-test (expected — proves pass() records a PASS)" >/dev/null
if [[ "$fails" != "1" || "$passes" != "1" ]]; then
  printf '[FATAL] HELPER CONTROL BROKEN: after one fail() and one pass(), fails=%s passes=%s (want 1/1)\n' "$fails" "$passes" >&2
  exit 1
fi
passes=0; fails=0

# 1. dependency-cruiser config — byte-identical to the template.
D="$(diff "$REF/depcruise-config.template" "$APP/.dependency-cruiser.cjs" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass ".dependency-cruiser.cjs is byte-identical to depcruise-config.template"
else
  fail ".dependency-cruiser.cjs DIVERGES from depcruise-config.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 2. shared runner — byte-identical to the template.
D="$(diff "$REF/shared-runner.template" "$APP/scripts/constraint-gates.sh" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "scripts/constraint-gates.sh is byte-identical to shared-runner.template"
else
  fail "scripts/constraint-gates.sh DIVERGES from shared-runner.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 3. apps/web-platform workflow == sed(__TARGET_DIR__ -> apps/web-platform) of the template.
SUBST="$(sed "s|__TARGET_DIR__|$TARGET_DIR|g" "$REF/constraint-gates-workflow.template")"
D="$(printf '%s\n' "$SUBST" | diff - "$APP/.github/workflows/constraint-gates.yml" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "apps/web-platform workflow == sed(__TARGET_DIR__) of the workflow template"
else
  fail "apps/web-platform workflow DIVERGES from the substituted template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 4. The folded repo-root gate == the template's constraint-gates job. Since
#    #8902 the dogfood instance lives inside `.github/workflows/pr-quality-guards.yml`
#    (the standalone root file was folded into the shared PR-gates workflow), and
#    since #12089 as the `constraint-gates*` member-step block of
#    `jobs.quality-advisory` (the standalone job was folded into the advisory
#    umbrella). Structural compare: the umbrella job's own checkout stands in
#    for the folded job's checkout step (same action pin and fetch-depth; extra
#    `with:` keys like persist-credentials are fold additions), and each member
#    step is compared to its template step after undoing the fold — the
#    `constraint-gates-` id prefix (`changed` -> `constraint-gates-changed`) and
#    the `${{ !cancelled() }}` member-standard `if:`.
strip_body() { grep -vE '^[[:space:]]*#' | grep -vE '^[[:space:]]*$' || true; }
D="$(python3 - "$SUBST" "$REPO_ROOT/.github/workflows/pr-quality-guards.yml" <<'PY' 2>&1 || true
import sys, yaml, re, difflib
tmpl = yaml.safe_load(sys.argv[1])["jobs"]["constraint-gates"]
root = yaml.safe_load(open(sys.argv[2]))["jobs"]["quality-advisory"]
problems = []

# the umbrella job's own checkout stands in for the folded job's checkout step
tco, rco = tmpl["steps"][0], root["steps"][0]
if rco.get("uses") != tco.get("uses"):
    problems.append("umbrella checkout uses %r != template %r" % (rco.get("uses"), tco.get("uses")))
if (rco.get("with") or {}).get("fetch-depth") != (tco.get("with") or {}).get("fetch-depth"):
    problems.append("umbrella checkout fetch-depth %r != template %r"
                    % ((rco.get("with") or {}).get("fetch-depth"), (tco.get("with") or {}).get("fetch-depth")))

# every member step carries the constraint-gates id prefix, in file order
mem = [s for s in root["steps"]
       if str(s.get("id", "")) == "constraint-gates" or str(s.get("id", "")).startswith("constraint-gates-")]
tsteps = tmpl["steps"][1:]
if len(mem) != len(tsteps):
    problems.append("member census: %d constraint-gates* steps in quality-advisory != %d template steps"
                    % (len(mem), len(tsteps)))
norm_mem = []
for ts, ms in zip(tsteps, mem):
    ms = dict(ms)
    if ms.get("name") != ts.get("name"):
        problems.append("member step %r order/name diverges from template step %r" % (ms.get("name"), ts.get("name")))
    mid = ms.pop("id", None)
    if ts.get("id") == "changed":
        # the fold renamed the detect step's id to constraint-gates-changed and gave
        # the previously unconditional step the member-standard ${{ !cancelled() }}
        if mid != "constraint-gates-changed":
            problems.append("detect member id %r != 'constraint-gates-changed'" % mid)
        ms["id"] = "changed"
        if ms.get("if") == "${{ !cancelled() }}":
            ms.pop("if")
        else:
            problems.append("detect member if: %r is not the fold-standard ${{ !cancelled() }}" % ms.get("if"))
    else:
        m = re.fullmatch(r"\$\{\{ !cancelled\(\) && (.*) \}\}", str(ms.get("if", "")))
        if m:
            ms["if"] = m.group(1).replace("steps.constraint-gates-changed", "steps.changed")
        else:
            problems.append("member step %r if: %r is not the ${{ !cancelled() && ... }} fold shape"
                            % (ms.get("name"), ms.get("if")))
    norm_mem.append(ms)

a = yaml.safe_dump(tsteps, sort_keys=True)
b = yaml.safe_dump(norm_mem, sort_keys=True)
if a != b:
    problems.append("\n".join(difflib.unified_diff(a.splitlines(), b.splitlines(),
          "template.jobs.constraint-gates.steps[1:]", "pr-quality-guards.jobs.quality-advisory.constraint-gates*",
          lineterm="")))
print("\n".join(problems))
PY
)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "constraint-gates* member steps of quality-advisory in pr-quality-guards.yml == substituted template job"
else
  fail "constraint-gates* member steps of quality-advisory DIVERGE from template job"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 5. repo-root dogfood Stage B == sed(__TARGET_DIR__) of the Stage B template (comment-stripped
#    body). Stage B is the PRIVILEGED, write-capable recovery consumer and carries the entire
#    fork-defense (isCrossRepository gate, path allowlist, sha256 round-trip, mandatory
#    base_tree); it has NO intentional dogfood divergence, so its body must match the tenant
#    template exactly. Guards the silent-drift class the emit test — which only inspects emitted
#    tenant fixtures, never the committed repo-root dogfood — structurally cannot catch (#5814).
B_ROOT="$REPO_ROOT/.github/workflows/fix-constraints-stage-b.yml"
STAGE_B_SUBST="$(sed "s|__TARGET_DIR__|$TARGET_DIR|g" "$REF/fix-constraints-stage-b.template")"
ROOT_B_BODY="$(strip_body < "$B_ROOT")"
TMPL_B_BODY="$(printf '%s\n' "$STAGE_B_SUBST" | strip_body)"
D="$(diff <(printf '%s\n' "$ROOT_B_BODY") <(printf '%s\n' "$TMPL_B_BODY") 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "repo-root fix-constraints-stage-b body == substituted Stage B template body"
else
  fail "repo-root fix-constraints-stage-b DIVERGES from the substituted template body"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 6. Dogfood security invariants on the two repo-root recovery workflows. Stage A intentionally
#    diverges from its template (dogfood-only api-spend steps + a richer anthropic-preflight
#    composite), so it gets invariant assertions rather than a body diff.
A_ROOT="$REPO_ROOT/.github/workflows/fix-constraints-stage-a.yml"

# 6a. Name-coupling: Stage A `name:` == Stage B `workflows:` filter (workflow_run matches by the
#     workflow's name, NOT its filename — a drift makes Stage B silently never trigger).
A_NAME="$(grep -E '^name:' "$A_ROOT" | head -1 | sed -E 's/^name:[[:space:]]*//' || true)"
B_WF="$(grep -E '^[[:space:]]+workflows:' "$B_ROOT" | head -1 | sed -E 's/.*workflows:[[:space:]]*\[[[:space:]]*"?([^]"]*)"?[[:space:]]*\].*/\1/' || true)"
cases=$((cases + 1))
if [[ -n "$A_NAME" && "$A_NAME" == "$B_WF" ]]; then
  pass "dogfood name-coupling: Stage A name: ('$A_NAME') == Stage B workflows: filter"
else
  fail "dogfood name-coupling BROKEN: Stage A name: ('$A_NAME') != Stage B workflows: ('$B_WF') — Stage B would never trigger"
fi

# 6a'. The same coupling on the TEMPLATES a founder repo receives: template A `name:` == template B
#      `workflows:` filter (the dogfood pair above can hold while the emitted pair drifts).
TA_NAME="$(grep -E '^name:' "$REF/fix-constraints-stage-a.template" | head -1 | sed -E 's/^name:[[:space:]]*//' || true)"
TB_WF="$(grep -E '^[[:space:]]+workflows:' "$REF/fix-constraints-stage-b.template" | head -1 | sed -E 's/.*workflows:[[:space:]]*\[[[:space:]]*"?([^]"]*)"?[[:space:]]*\].*/\1/' || true)"
cases=$((cases + 1))
if [[ -n "$TA_NAME" && "$TA_NAME" == "$TB_WF" ]]; then
  pass "template name-coupling: Stage A template name: ('$TA_NAME') == Stage B template workflows: filter"
else
  fail "template name-coupling BROKEN: Stage A template name: ('$TA_NAME') != Stage B template workflows: ('$TB_WF')"
fi

# 6b. Stage B (privileged) executes no untrusted tree: no checkout-of-head / bun install /
#     git apply in its executable body (full-line comments stripped so the header's prose that
#     NAMES these constructs cannot false-match).
B_CODE="$(grep -vE '^[[:space:]]*#' "$B_ROOT" || true)"
bfail=0
if grep -qE '(^|[[:space:]-])uses:[[:space:]]*actions/checkout' "$B_ROOT"; then bfail=1; fi
for tok in 'bun install' 'setup-bun' 'git apply'; do
  if printf '%s\n' "$B_CODE" | grep -cF >/dev/null "$tok"; then bfail=1; fi
done
cases=$((cases + 1))
if [[ "$bfail" -eq 0 ]]; then
  pass "dogfood Stage B executes no untrusted tree (no checkout/bun-install/git-apply)"
else
  fail "dogfood Stage B contains a forbidden execution construct (checkout/bun-install/git-apply)"
fi

# 6c. Stage A (untrusted producer) is read-only: declares contents: read, never contents: write.
cases=$((cases + 1))
if grep -qE '^[[:space:]]*contents:[[:space:]]*read' "$A_ROOT" && ! grep -qE '^[[:space:]]*contents:[[:space:]]*write' "$A_ROOT"; then
  pass "dogfood Stage A is read-only (contents: read, no contents: write)"
else
  fail "dogfood Stage A permission drift: expected contents: read only, found a write scope"
fi

# 7. Dogfood README block == the EMITTER's transform of boundary-readme.template (first-line
#    attribution stripped, __TARGET_DIR__ substituted). `-s` FIRST: a `diff` of two empty
#    operands passes, which is the parity vacuity that matters. The strip expression is pinned by
#    `grep -cF` against the script's `content="$(sed …` ASSIGNMENT (a stale comment quoting the
#    expression cannot stand in for the live one) so the two copies of the one transform cannot
#    diverge silently. The comparison normalises trailing newlines exactly as the emitter does
#    (`content="$(…)"` then `printf '%s\n'`), so a template ending in 0 or 2 newlines compares
#    against what the emitter actually writes.
README_TMPL="$REF/boundary-readme.template"
README_DOG="$APP/server/README.md"
STRIP_EXPR="sed -e '1{/^<!-- Inspired by /d;}' -e \"s|__TARGET_DIR__|\$TARGET_REL|g\""
GEN_SCRIPT="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
STRIP_PIN="$(grep -E '^\s*content="\$\(sed ' "$GEN_SCRIPT" 2>/dev/null | grep -cF -- "$STRIP_EXPR" || true)"
D=""
if [[ ! -s "$README_TMPL" ]]; then
  D="template $README_TMPL is missing or empty"
elif [[ ! -s "$README_DOG" ]]; then
  D="dogfood $README_DOG is missing or empty"
elif [[ "$STRIP_PIN" != "1" ]]; then
  D="strip expression pin: the script contains the literal emitter expression $STRIP_PIN time(s), expected exactly 1"
elif ! head -1 "$README_TMPL" | grep -c >/dev/null '^<!-- Inspired by '; then
  D="template line 1 is not the attribution comment (the emitter strips exactly that line)"
else
  EXPECTED_README="$(sed -e '1{/^<!-- Inspired by /d;}' -e "s|__TARGET_DIR__|$TARGET_DIR|g" "$README_TMPL")"
  D="$(printf '%s\n' "$EXPECTED_README" | diff - "$README_DOG" 2>&1 || true)"
fi
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "apps/web-platform/server/README.md == emitter transform of boundary-readme.template (non-empty; strip expression pinned)"
else
  fail "apps/web-platform/server/README.md DIVERGES from the template transform"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 8. Repo-root CLAUDE.md carries the pointer marker EXACTLY once, on a line naming the dogfood
#    README path, with no `@apps/` import form (an `@path` line is a Claude Code import and would
#    load the README into every session). Four selections for a four-dimension claim.
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
POINTER_MARKER='<!-- constraint-scaffold:pointer -->'
PTR_CT="$(grep -c -- "$POINTER_MARKER" "$CLAUDE_MD" 2>/dev/null || true)"
PTR_LINE="$(grep -- "$POINTER_MARKER" "$CLAUDE_MD" 2>/dev/null | head -1 || true)"
D=""
if [[ ! -s "$CLAUDE_MD" ]]; then
  D="CLAUDE.md is missing or empty"
elif [[ "$PTR_CT" != "1" ]]; then
  D="pointer marker appears $PTR_CT time(s), expected exactly 1"
elif [[ "$PTR_LINE" != *"apps/web-platform/server/README.md"* ]]; then
  D="pointer line does not name apps/web-platform/server/README.md: '$PTR_LINE'"
elif [[ "$PTR_LINE" == *"@apps/"* ]]; then
  D="pointer line uses the forbidden @apps/ import form: '$PTR_LINE'"
fi
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "CLAUDE.md carries the constraint-scaffold pointer once, naming the README path, without @apps/"
else
  fail "CLAUDE.md pointer: $D"
fi

# 9. Emission census: every `cp`/`sed` of a `$REF_DIR/*.template` in the script's default-mode
#    emit block has a parity row above (rows 1–5 read one template each; the README template is
#    row 7). A sixth emitted template with no dogfood row would otherwise red nothing here.
EMITTED_TEMPLATES="$(grep -oE '"\$REF_DIR/[a-z-]+\.template"' "$GEN_SCRIPT" 2>/dev/null | sort -u | grep -c . || true)"
ROW_TEMPLATES="$(grep -oE '"\$REF/[a-z-]+\.template"' "${BASH_SOURCE[0]}" | sort -u | grep -c . || true)"
cases=$((cases + 1))
if [[ "$EMITTED_TEMPLATES" -ge 6 && "$EMITTED_TEMPLATES" == "$ROW_TEMPLATES" ]]; then
  pass "emission census: the script reads $EMITTED_TEMPLATES distinct templates and this suite has a row for each"
else
  fail "emission census: script reads $EMITTED_TEMPLATES distinct templates, this suite reads $ROW_TEMPLATES (want equal, >= 6)"
fi

echo "---"

# --- Accounting conservation (ADR-193 #3) --------------------------------------------------
# Ordered BEFORE the floor (ADR-193 #4): a neutered fail()/pass() deflates the verdict counters, so
# the floor below would ALSO trip and would report the misleading "arms were deleted". This says
# "a verdict was discarded" instead. Reported with `printf >&2` + `exit 1` DIRECTLY, never
# through fail(): a check that reports by calling the verdict helper increments the very counter
# the exit status reads, so neutering fail() silences the rows AND the check meant to notice the
# silence. Every row records exactly one verdict, so passes+fails MUST equal cases; because
# `cases` moves at the CALL SITE and not inside the verdict helpers, the identity is a real
# constraint rather than a tautology. The literal `[FATAL] accounting` is load-bearing —
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that exact string.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if [[ $((passes + fails)) -lt "$cases" ]]; then
    printf '  A row was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1) -------------------------------------------------------
# Reads the INDEPENDENT `cases` counter, and reports with `printf >&2` + `exit 1` DIRECTLY.
# This suite previously carried NO suite-level floor at all: a harness that silently asserted
# nothing printed a clean smaller total and exited 0. MIN_ROWS is derived at commit time by
# counting the `cases=$((cases + 1))` call sites in this file: 8 pre-existing verdict sites (rows
# 1, 2, 3, 4, 5, 6a, 6b, 6c) + rows 7–8 = 10. The literal sits on the line directly above the `if`
# because guard-vacuity-floor's backward slice carries only contiguous simple assignments into
# its neutered-machinery mutant; bound anywhere else, the mutant dies unbound and the floor
# scores CONSTRUCTION instead of FIRES.
MIN_ROWS=12
if [[ "$cases" -lt "$MIN_ROWS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ROWS" >&2
  printf '  Rows were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
[[ "$fails" -eq 0 ]]
