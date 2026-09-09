#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guards 3/4/5/7/8 (#5806, ADR-215) — the workflow_run deploy gate.
#
# SUCCESSOR TO await-ci-ceiling-invariants.test.sh, renamed rather than deleted.
# That suite guarded the constants of a polling job that no longer exists. Its
# rows I1/I2 (poll-loop attempt arithmetic) retire WITH the loop; I3 (derived,
# never restated), I3b (the warning fires below its reference) and I4 (the
# emitted signal has a consumer) SURVIVE with a new subject — the CI-budget
# derivation that replaced the deleted ceiling. `git log --follow` on this path
# reaches the old suite, so the lineage is re-derivable.
#
# WHAT THE WHOLE FILE IS FOR. `deploy` swaps the LIVE production site. The
# change these rows guard moved the trigger for that swap onto a different
# workflow's completion event, which introduced two failure shapes that are
# invisible to YAML review:
#
#   1. A FAIL-OPEN. The verdict that stops a mirror-gate-blocked release from
#      deploying an unmirrored image (`release.result`) had to be recovered
#      across a run boundary. The tempting reconstruction — read the artifact's
#      `mirror_verified`, it is right there — is WRONG, because that field is
#      documented as deliberately non-blocking and `docker_pushed` is written
#      ten steps before the gate it appears to represent. Row G3-13b is the only
#      thing standing between a future editor and that substitution.
#   2. A FAIL-CLOSED-ON-EVERYTHING. `workflow_run` inherits neither of the two
#      path gates, so it fires on every main CI completion including docs-only
#      pushes. Collapsing "correctly published nothing" into "the release is
#      missing" reddens routine commits until the signal means nothing.
#
# Both are states the happy path never visits, which is why they need a battery
# rather than a reading.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
REL="$REPO_ROOT/.github/workflows/web-platform-release.yml"
CI="$REPO_ROOT/.github/workflows/ci.yml"
REUSABLE="$REPO_ROOT/.github/workflows/reusable-release.yml"
DRIFT="$REPO_ROOT/scripts/prod-version-drift-check.sh"

for f in "$REL" "$CI" "$REUSABLE" "$DRIFT"; do
  [ -f "$f" ] || { printf 'FAIL: %s not found\n' "$f" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL: PyYAML required\n' >&2; exit 2; }

W=$(mktemp -d -t wrdeploy.XXXXXXXX) || { printf 'FAIL: mktemp\n' >&2; exit 2; }
trap 'rm -rf "$W"' EXIT

echo "=== Guards 3/4/5/7/8: the workflow_run deploy gate (#5806) ==="

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() increments)"
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test — helpers did not both move\n' >&2; exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── Structural analyser ──────────────────────────────────────────────────────
# Job reachability on the workflow_run arm is COMPUTED from each job's `if:` and
# the `needs:` closure — never a checked-in list of the jobs that exist today,
# which would go stale the moment a job is added. That staleness is the whole
# point of mutation row G3-11.
ANALYSE="$W/analyse.py"
cat > "$ANALYSE" <<'PY'
import sys, json, yaml, re

wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf.get("jobs") or {}
on = wf.get(True) or wf.get("on") or {}

def needs_of(n):
    v = (jobs.get(n) or {}).get("needs") or []
    return [v] if isinstance(v, str) else list(v)

def cond(n):
    return " ".join(str((jobs.get(n) or {}).get("if", "")).split())

# A job is reachable on the workflow_run arm unless its own `if:` excludes that
# event, or every path to it runs through a job that does.
def excludes_wr(n):
    c = cond(n)
    if not c:
        return False
    if "github.event_name != 'workflow_run'" in c:
        return True
    if "github.event_name == 'push'" in c and "workflow_run" not in c:
        return True
    if "github.event_name == 'workflow_dispatch'" in c and "workflow_run" not in c:
        return True
    return False

reachable = []
for n in jobs:
    if excludes_wr(n):
        continue
    # a job whose entire needs-closure is excluded cannot run on this arm either
    stack, seen, blocked = list(needs_of(n)), set(), False
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        stack.extend(needs_of(cur))
    reachable.append(n)

out = {
    "triggers": sorted(on.keys()) if isinstance(on, dict) else [],
    "wr_workflows": ((on.get("workflow_run") or {}).get("workflows") or []) if isinstance(on, dict) else [],
    "wr_branches": ((on.get("workflow_run") or {}).get("branches") or []) if isinstance(on, dict) else [],
    "jobs": sorted(jobs.keys()),
    "wr_reachable": sorted(reachable),
    "conds": {n: cond(n) for n in jobs},
    "needs": {n: needs_of(n) for n in jobs},
}
# Every `${{ github.sha }}` occurrence, attributed to its owning job, by
# structural line-walk over the raw source (the parsed doc loses line origin).
src = open(sys.argv[1]).read().split("\n")
job = None
sha_sites = []
injobs = False
for i, l in enumerate(src, 1):
    if re.match(r"^jobs:\s*$", l):
        injobs = True
        continue
    if not injobs:
        continue
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", l)
    if m:
        job = m.group(1)
    if l.lstrip().startswith("#"):
        continue
    # MATCH `github.sha` AS A TOKEN INSIDE ANY `${{ }}` SPAN, not as the exact
    # three-token literal. The literal form is one spelling among many: this PR
    # itself introduced five sites of the shape
    #   ref: ${{ needs.<job>.outputs.head_sha || github.sha }}
    # and an exact-literal match was blind to every one of them, so G3's headline
    # claim was already false of the file it guards. `${{github.sha}}` (no inner
    # spaces) and a span folded across lines were equally invisible.
    for span in re.findall(r"\$\{\{(.*?)\}\}", l, re.S):
        if not re.search(r"(?<![.\w])github\.sha(?![\w])", span):
            continue
        norm = " ".join(span.split())
        # PERMIT (semantic, not name-keyed): `<upstream>.head_sha || github.sha`.
        # `||` in a GitHub expression yields the right operand only when the left
        # is falsy, and `github.event.workflow_run.head_sha` is non-empty on EVERY
        # workflow_run event. So github.sha here is reachable only when the run is
        # NOT a workflow_run — i.e. never on the arm this guard is about. A job
        # that `needs: resolve-target` has no business using this form (its
        # head_sha is 40-hex-validated upstream), and gets no permit.
        if re.fullmatch(r"github\.event\.workflow_run\.head_sha \|\| github\.sha", norm):
            continue
        sha_sites.append({"line": i, "job": job, "text": l.strip(), "expr": norm})
        break
    if "github.event.before" in l:
        sha_sites.append({"line": i, "job": job, "text": l.strip(), "before": True})
out["sha_sites"] = sha_sites
print(json.dumps(out))
PY

A="$W/a.json"
if ! python3 "$ANALYSE" "$REL" > "$A" 2>"$W/a.err"; then
  printf 'FAIL: analyser could not parse %s: %s\n' "$REL" "$(cat "$W/a.err")" >&2; exit 2
fi
jqa() { python3 -c "import json,sys;d=json.load(open('$A'));print($1)"; }

# ANALYSER SELF-TEST: prove it can SEE a workflow_run-reachable job before
# trusting it to report their absence. An extractor that finds nothing reports
# "no violations" and "nothing to check" identically.
_n_reach=$(jqa "len(d['wr_reachable'])")
if [ "$_n_reach" -ge 3 ]; then pass; else
  printf 'FAIL: ANALYSER SELF-TEST — only %s workflow_run-reachable jobs found; every "no violations" verdict below would be unfalsifiable\n' "$_n_reach" >&2
  exit 2
fi
echo "  analyser self-test: $_n_reach workflow_run-reachable jobs found"

# ═══ GUARD 4 — the trigger matches ci.yml's `name:`, not its filename ════════
CI_NAME=$(python3 -c "import yaml;print((yaml.safe_load(open('$CI')) or {}).get('name',''))")
if [ -n "$CI_NAME" ]; then pass; else fail "G4 ci.yml declares no name:"; fi

# Every workflow_run consumer in the repo that intends to match it — discovered
# by grep, not by naming two files. post-merge-monitor.yml already depends on
# the same string and must be covered (mutation row G4-16).
_wr_consumers=$(cd "$REPO_ROOT" && git grep -l 'workflow_run:' -- .github/workflows/ 2>/dev/null)
_n_cons=$(printf '%s\n' "$_wr_consumers" | grep -c . || true)
if [ "$_n_cons" -ge 2 ]; then pass; else
  fail "G4 only $_n_cons workflow_run consumer(s) discovered — the guard has nothing to cross-check and mutation G4-16 could not fire"
fi
_desync=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _lists=$(python3 - "$REPO_ROOT/$f" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
on = d.get(True) or d.get("on") or {}
wr = (on.get("workflow_run") or {}) if isinstance(on, dict) else {}
print("\n".join(wr.get("workflows") or []))
PY
)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # Only CI consumers are in scope: a workflow_run on some OTHER workflow is
    # not a desync with ci.yml.
    case "$name" in
      "$CI_NAME") : ;;
      CI|ci) _desync="${_desync}${f} names '${name}' but ci.yml declares '${CI_NAME}'; " ;;
    esac
  done <<< "$_lists"
done <<< "$_wr_consumers"
if [ -z "$_desync" ]; then pass; else fail "G4 workflow_run/name desync: $_desync"; fi

# The deploy arm must actually name it.
if printf '%s' "$(jqa "d['wr_workflows']")" | grep -qF -- "$CI_NAME"; then pass; else
  fail "G4 web-platform-release.yml workflow_run.workflows does not name ci.yml's '$CI_NAME': $(jqa "d['wr_workflows']")"
fi
# `branches:` is not optional — without it a full run is created for every PR
# and merge_group CI completion.
if printf '%s' "$(jqa "d['wr_branches']")" | grep -qF 'main'; then pass; else
  fail "G4 workflow_run has no branches: [main] filter — a full run would be created for every PR and merge_group CI completion"
fi

# ═══ GUARD 3 — no workflow_run-reachable path reads bare github.sha ══════════
# The ASSEMBLY is computed, not listed: every `${{ github.sha }}` site
# intersected with the reachable-job set.
# THE ONE PERMITTED SITE, NARROWLY. `resolve-target` runs on BOTH non-push arms
# and its workflow_dispatch branch legitimately targets `github.sha` — on a
# dispatch there IS no upstream event to read a head_sha from, and the operator
# is deliberately deploying the current default-branch tip. Left absolute, this
# guard reds the correct implementation.
#
# The permit is keyed on the env NAME `DISPATCH_SHA`, which declares its own
# scope, and is additionally required to live in `resolve-target` AND to be
# consumed only under a workflow_dispatch branch. Anything else — including a
# second `github.sha` in the same job under a different name — still fails.
_bad_sha=$(python3 -c "
import json
d=json.load(open('$A'))
reach=set(d['wr_reachable'])
def permitted(s):
    return s['job'] == 'resolve-target' and s['text'].startswith('DISPATCH_SHA:')
bad=[s for s in d['sha_sites'] if not s.get('before') and s['job'] in reach and not permitted(s)]
print('; '.join('%s:%d %s'%(b['job'],b['line'],b['text'][:60]) for b in bad))
")
if [ -z "$_bad_sha" ]; then pass; else
  fail "G3 a workflow_run-reachable job reads bare \${{ github.sha }} — under workflow_run that is the DEFAULT-BRANCH tip, not the SHA CI verified: $_bad_sha"
fi
# THE PERMIT IS NOT A HOLE — these two rows are what bound it. Without them
# "name it DISPATCH_SHA" would be a way to smuggle a default-branch SHA onto the
# workflow_run arm.
if grep -qE 'DISPATCH_SHA' "$W/resolve.blk" 2>/dev/null || grep -qE 'DISPATCH_SHA' "$REL"; then
  # It must be consumed ONLY under the dispatch branch.
  if awk '/if \[ "\$EVENT_NAME" = "workflow_dispatch" \]/{f=1} f&&/^          fi$/{exit} f' "$REL" | grep -qF 'DISPATCH_SHA'; then
    pass
  else
    fail "G3 DISPATCH_SHA is read OUTSIDE the workflow_dispatch branch — the permit exists only because that value is unreachable on the workflow_run arm"
  fi
else
  pass
fi
# Exactly one such permitted site. A second would mean the name is being used as
# a bypass rather than as a scope declaration.
_n_dispatch_sha=$(grep -cE '^\s*DISPATCH_SHA:' "$REL" || true)
if [ "$_n_dispatch_sha" -le 1 ]; then pass; else
  fail "G3 $_n_dispatch_sha DISPATCH_SHA sites — the permit covers exactly one, in resolve-target; more means it is being used to smuggle github.sha onto the workflow_run arm"
fi

# G3-12 — live-verify must not be gated on the push event, which would skip it
# forever now that the deploy never runs on a push.
_lv=$(jqa "d['conds'].get('live-verify','')")
case "$_lv" in
  *"github.event_name == 'push'"*)
    fail "G3-12 live-verify is gated on github.event_name == 'push' — the deploy never runs on push under this topology, so it would skip FOREVER while the run stays green" ;;
  *) pass ;;
esac
# `github.event.before` does not exist on a workflow_run event; it resolves to
# the empty string and a compare-API diff with an empty base matches nothing
# WITHOUT erroring — a silent SKIP of the dark-launch gate.
_before=$(python3 -c "
import json
d=json.load(open('$A'))
reach=set(d['wr_reachable'])
bad=[s for s in d['sha_sites'] if s.get('before') and s['job'] in reach]
print('; '.join('%s:%d'%(b['job'],b['line']) for b in bad))
")
if [ -z "$_before" ]; then pass; else
  fail "G3 a workflow_run-reachable job reads github.event.before, which does not exist on that event (resolves to empty; a compare with an empty base silently matches nothing): $_before"
fi

# G3-13b — THE EQUAL-STRENGTH ROW. The deploy verdict must come from the release
# JOB's conclusion, never from the artifact's mirror_verified/docker_pushed.
_resolve_body=$(awk '/^  resolve-target:/{f=1} f&&/^  [a-zA-Z0-9_-]+:$/&&!/^  resolve-target:/{exit} f' "$REL")
printf '%s' "$_resolve_body" > "$W/resolve.blk"
# COMMENT-STRIPPED HAYSTACK. `resolve.blk` is the raw job block, so a row
# anchored on a token was satisfied by the COMMENT EXPLAINING the pin and by the
# error-message STRING naming it. Measured: mutating
# `select(.name == "release / release")` to `select(.name == "release")` — the
# literal fail-open G3-13b exists to prevent — left this suite GREEN, shadowed
# twice. Same for `event=push`. Anchor on the call form, in code only.
sed -e 's/[[:space:]]*#.*$//' "$W/resolve.blk" > "$W/resolve.code"
# The stripper must not eat the file: a comment-only haystack and an EMPTY one
# both make every row below vacuously pass.
if [ -s "$W/resolve.code" ] && [ "$(grep -c . "$W/resolve.code")" -ge 40 ]; then pass; else
  fail "G3 the comment-stripped resolve-target body is empty or implausibly short ($(grep -c . "$W/resolve.code" 2>/dev/null || echo 0) code lines) — every anchored row below would pass vacuously"
fi
if grep -qF 'select(.name == "release / release")' "$W/resolve.code"; then pass; else
  fail "G3-13b resolve-target does not pin the literal job name 'release / release'. The bare name is a REUSABLE-WORKFLOW call, so a lookup on the bare name matches ZERO rows and the guard fails OPEN"
fi
if grep -qE 'release_result.*!=.*success|\[ "\$release_result" != "success" \]' "$W/resolve.blk"; then pass; else
  fail "G3-13b resolve-target does not fail closed on a non-success release job conclusion — this is the ONLY thing between a mirror-gate-blocked release and a prod deploy of an unmirrored image"
fi
# The substitution row: mirror_verified must not appear in a gating comparison.
if grep -qE '^\s*if.*mirror_verified.*(!=|==).*(true|false)' "$W/resolve.blk"; then
  fail "G3-13b resolve-target GATES on mirror_verified. It is documented as deliberately NON-blocking, and docker_pushed is written ten steps before the mirror assertion — gating on either restores the fail-open that needs.release.result was written to close"
else pass; fi

# ═══ GUARD 7 — the five states, and the two that must stay GREEN ═════════════
# Discovered from the job body, never from a list of expected states.
for st in no_release_run upstream_concluded_unpublished release_failed; do
  if grep -qF "$st" "$W/resolve.blk"; then pass; else
    fail "G7 resolve-target has no '$st' state — the five-state resolution is incomplete and states will be collapsed"
  fi
done
# The two clean skips must exit 0 (green); the failure state must exit non-zero.
if awk '/clean_skip\(\) \{/{f=1} f&&/^          \}/{exit} f' "$W/resolve.code" | grep -qE '^\s*exit 0\s*$'; then pass; else
  fail "G7 resolve-target has no clean-skip path that leaves the run GREEN — a docs-only push would redden the release run"
fi
if awk '/fail_closed\(\) \{/{f=1} f&&/^          \}/{exit} f' "$W/resolve.code" | grep -qE '^\s*exit 1\s*$'; then pass; else
  fail "G7 resolve-target has no fail-closed path — a genuinely failed release would be swallowed as a skip"
fi
# The own-run exclusion. Without it the query resolves state 2 for a SHA that
# DID publish, and the deploy silently never happens while the run stays green.
if grep -qE 'runs\?[^"]*event=push' "$W/resolve.code" && grep -qE 'OWN_RUN_ID|github\.run_id' "$W/resolve.code"; then pass; else
  fail "G7 resolve-target's run lookup is not pinned to ?event=push AND excluding its own run id — the new topology produces runs for the SAME sha on both arms, so an unfiltered query resolves 'published nothing' for a SHA that did publish"
fi
# Identity + schema bindings: the artifact CONFIRMS, never SUPPLIES.
if grep -qE 'identity_mismatch' "$W/resolve.blk"; then pass; else
  fail "G7 resolve-target does not assert the artifact's head_sha/run_id against the trusted event — identity must come from the event, never from the artifact"
fi
if grep -qE 'schema_mismatch' "$W/resolve.blk"; then pass; else
  fail "G7 resolve-target does not assert the artifact schema — a rename in the shared workflow would yield empty strings instead of failing closed"
fi
# notify-gated must NOT fire on the clean-skip states.
_ng=$(jqa "d['conds'].get('notify-gated','')")
case "$_ng" in
  *no_release_run*|*upstream_concluded_unpublished*)
    fail "G7 notify-gated fires on a CLEAN-SKIP state — every docs-only push would page the operator until the channel stops carrying information" ;;
  *) pass ;;
esac
case "$_ng" in
  *"conclusion != 'success'"*) pass ;;
  *) fail "G7 notify-gated does not fire on a non-success CI conclusion; with await-ci gone a RED CI on main would produce a GREEN release run and ZERO notifications" ;;
esac

# ═══ GUARD 5 — every ceiling on the new path is DERIVED, never restated ══════
# TERMINATE AT THE JOB BOUNDARY TOO. The budget step is the LAST step of
# resolve-target, so there is no following `- name:` at its indent: the previous
# form ran off the end of the job and captured 251 lines spanning resolve-target
# AND migrate. Every `grep -qF <jobname>` row below was then satisfiable by a
# FOREIGN job's text — the extractor self-test asked "did it find >= N?", never
# "did it find only the right region?", which is how it went unnoticed.
_budget=$(awk '
  /- name: Derive the CI budget/{f=1}
  f && /^      - name: / && !/Derive the CI budget/{exit}
  f && /^  [a-zA-Z0-9_-]+:$/{exit}
  f' "$REL")
printf '%s' "$_budget" > "$W/budget.blk"
if [ -s "$W/budget.blk" ]; then pass; else
  fail "G5 the CI-budget derivation step was not found — the creep detector deleted with await-ci was not relocated (ADR-212 Decision 4 regression)"
fi
# EXTRACTOR SCOPE SELF-TEST. Presence is not scope. Assert the captured region
# is bounded by the job it claims to be, so an over-capture cannot vouch for the
# rows that read it.
if grep -qE '^  [a-zA-Z0-9_-]+:$' "$W/budget.blk"; then
  fail "G5 the budget extraction crossed a JOB boundary ($(grep -cE '^  [a-zA-Z0-9_-]+:$' "$W/budget.blk") job header(s) inside it, $(wc -l < "$W/budget.blk") lines) — every jobname row below could then be satisfied by a foreign job"
else pass; fi
# I3's successor: DERIVED from a read value, never a literal.
if grep -qE 'THRESHOLD=\$\(read_threshold\)' "$W/budget.blk"; then pass; else
  fail "G5-18 the pipeline threshold is not READ from the tree — a restated literal drifts silently the moment DRIFT_SUSTAINED_THRESHOLD_MIN moves"
fi
if grep -qE 'CI_BUDGET_MIN=\$\(\(\s*THRESHOLD' "$W/budget.blk"; then pass; else
  fail "G5-18 CI_BUDGET_MIN is not derived from THRESHOLD minus the downstream ceilings"
fi
# THE FIFTH INPUT. Without it, lowering test-scripts' ceiling silently stops the
# detector tracking the thing it detects.
# ANCHORED ON THE CALL, NOT THE NAME. `grep -qF test` matched inside
# `test-scripts`, so deleting the `test` input left the count at 5; and all five
# names also appear in this step's ERROR-MESSAGE PROSE and in its validation
# list, so the count survived deleting the job_ceiling call itself. Both are the
# assert-anchor-not-bare-token class. The set is also SMALLER now: test-scripts
# and test were the wrong quantity (see the CI_DECLARED_PATH comment in the
# workflow) and were replaced by a whole-run closure.
_missing=""
for jobname in migrate verify-migrations deploy; do
  grep -qF -- "job_ceiling \"\$REL\" ${jobname})" "$W/budget.blk" \
    || _missing="${_missing}${jobname} "
done
for helper in undeclared_jobs run_declared_path; do
  grep -qE "^\s*${helper}\(\) \{" "$W/budget.blk" || _missing="${_missing}${helper}() "
done
grep -qE 'undeclared_jobs \.github/workflows/ci\.yml' "$W/budget.blk" \
  || _missing="${_missing}undeclared_jobs(ci.yml)-call "
if [ -z "$_missing" ]; then pass; else
  fail "G5-21 the derivation does not read these inputs by their CALL form: ${_missing}— each is a ceiling the creep detector tracks, and a bare-name grep here was satisfied by the step's own error-message prose"
fi
# I3b's successor: the warning must fire BELOW its reference, not at or above.
if grep -qE '\* 60 \* 7 / 10' "$W/budget.blk"; then pass; else
  fail "G5-19 the soft ceiling is not 0.7x its reference — a factor at or above 1.0 means the warning never fires before the budget is already blown"
fi
# The headroom invariant is asserted, not assumed.
if grep -qE 'CI_DECLARED_PATH_MIN.*-gt.*CI_BUDGET_MIN' "$W/budget.blk"; then pass; else
  fail "G5 the CI_DECLARED_PATH <= CI_BUDGET_MIN headroom is not asserted — the two quantities were conflated once already and nothing would catch it recurring"
fi
# I4's successor: the emitted signal HAS a consumer.
if grep -qF 'needs.resolve-target.outputs.soft_breach' "$REL"; then pass; else
  fail "G5-20 nothing consumes resolve-target's soft_breach output — a warning nobody reads is a warning nobody sees, which is the regression I4 existed to catch"
fi

# ═══ GUARD 8 — every consumer disambiguates the two arms ═════════════════════
# ASSEMBLY BY EXTRACTION, and the extraction is the part that was wrong.
#
# An earlier revision grepped the single literal `workflow=web-platform-release`
# across `plugins/ scripts/ .github/`. That found TWO rows — and FOUR of the six
# call sites THIS PR ITSELF SWEPT were invisible to it: `--workflow ` with a space
# (postmerge/SKILL.md, ship/SKILL.md), `--workflow="$WORKFLOW"` via a variable
# (watch-live-verify-pass.sh), `gh api .../workflows/${WORKFLOW}/runs`
# (zot-mirror-connector-6416.sh), and everything under knowledge-base/, which was
# outside the path scope entirely. The non-vacuity floor (>= 1) was satisfied by
# the two incidental survivors, so the guard reported healthy while covering
# almost nothing — a guard narrower than the property it names.
#
# The discovery now keys on the WORKFLOW being selected (by file name, however
# spelled) rather than on one flag spelling, and covers knowledge-base too.
_consumers=$(cd "$REPO_ROOT" && git grep -nE \
  'gh run (list|view|watch|rerun)[^|]*web-platform-release|workflows/[^ ]*web-platform-release[^ ]*/runs|WORKFLOW="?web-platform-release' \
  -- plugins/ scripts/ .github/ knowledge-base/ 2>/dev/null \
  | grep -v 'workflow-run-deploy-invariants' \
  | grep -vE '^knowledge-base/project/(plans|specs)/|/archive/|post-mortems/' || true)
_n_consumers=$(printf '%s\n' "$_consumers" | grep -c . || true)

# NON-VACUITY: the count must exceed what the OLD broken predicate found, or the
# extraction has silently narrowed again. 2 was the broken value; the swept set is
# materially larger. A floor of 5 is below the current population and above the
# degenerate one, so a re-narrowing reds rather than reporting clean.
if [ "$_n_consumers" -ge 5 ]; then pass; else
  fail "G8 the consumer extraction found only $_n_consumers call site(s) — the broken predicate found 2 and this PR swept six. The extraction has narrowed; a 'no violations' verdict from it is unfalsifiable"
fi

_undis=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  _f="${hit%%:*}"; _rest="${hit#*:}"; _ln="${_rest%%:*}"
  case "$_ln" in ''|*[!0-9]*) continue ;; esac
  # SCOPE THE CHECK TO THE COMMAND, NOT THE LINE. A `gh run list ... \` continues
  # onto the next line, and a `WORKFLOW="web-platform-release.yml"` assignment is
  # resolved at a `gh` call further down — so a single-line predicate reports a
  # correctly-disambiguated consumer as a violation. The window is the property's
  # real domain. (It is deliberately NOT the whole file: that would let an
  # unrelated `--event` elsewhere vouch for this call site.)
  _lo=$(( _ln > 3 ? _ln - 3 : 1 )); _hi=$(( _ln + 12 ))
  _win=$(sed -n "${_lo},${_hi}p" "$REPO_ROOT/$_f" 2>/dev/null)
  case "$_win" in
    *"--event workflow_run"*|*"--event push"*|*"event=push"*|*"event=workflow_run"*|*'EVENT_ARM'*) : ;;
    *) _undis="${_undis}${hit}
" ;;
  esac
done <<< "$_consumers"

if [ -z "$_undis" ]; then pass; else
  fail "G8 consumer(s) select a web-platform-release run without naming an arm — after the split each merge produces BOTH, so these read the wrong half ~50% of the time:
$_undis"
fi

# The mutant predicate is the SUITE'S OWN GUARDS, not a paraphrase of them.
# It previously omitted G3's `before` and `permitted()` filters, so it reported a
# violation on the UNMUTATED file (resolve-target's legitimate `DISPATCH_SHA:
# ${{ github.sha }}` is workflow_run-reachable). Every row then scored KILLED
# whatever it mutated, including a mutant that changed nothing semantic — so
# "5/5 killed" was a reading of the baseline, and G4-15 was in fact SURVIVING.
# The MUT-CONTROL rows below are what keep this honest: the predicate must be
# EMPTY on the pristine file, and a null mutant must be reported SURVIVING.
MUTPRED="$W/mutpred.py"
cat > "$MUTPRED" <<'PYPRED'
import json, os
d = json.load(open(os.environ["MUT_A"]))
reach = set(d["wr_reachable"])
def permitted(s):                                   # identical to the G3 row
    return s["job"] == "resolve-target" and s["text"].startswith("DISPATCH_SHA:")
out = []
if [s for s in d["sha_sites"]
    if not s.get("before") and s["job"] in reach and not permitted(s)]:
    out.append("sha")
if [s for s in d["sha_sites"] if s.get("before") and s["job"] in reach]:
    out.append("before")
if "github.event_name == 'push'" in d["conds"].get("live-verify", ""):
    out.append("lv-push")
if "main" not in (d["wr_branches"] or []):
    out.append("branches")
if not d["wr_workflows"]:
    out.append("workflows")
# G4-15 is a NAME DESYNC, not an emptiness: `workflows:` naming something that is
# not ci.yml's `name:` is the defect, and the old predicate never compared them.
CI_NAME = os.environ.get("MUT_CI_NAME", "")
if CI_NAME and CI_NAME not in (d["wr_workflows"] or []):
    out.append("wf-name")
print(",".join(out))
PYPRED
# CI_NAME is already derived from $CI at Guard 4 — reuse it rather than
# re-deriving (a second derivation is a second thing that can drift).
if [ -z "${CI_NAME:-}" ]; then
  printf 'FATAL: CI_NAME is empty — the wf-name mutant row would be vacuous\n' >&2
  exit 1
fi

# ═══ MUTATION BATTERY ════════════════════════════════════════════════════════
MUT_TOTAL=0; MUT_KILLED=0; MUT_SURVIVED=()
mutate() {  # $1=label $2=sed-expr $3=grep-pattern the MUTATED analysis must trip
  local label="$1" expr="$2"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  local m="$W/mut.$RANDOM.yml"
  sed "$expr" "$REL" > "$m"
  if cmp -s "$m" "$REL"; then
    fail "MUTATION DID NOT LAND: $label — sed matched nothing, so this row measured the BASELINE"
    return
  fi
  # Re-run the structural analyser over the mutant and re-apply the guard that
  # should catch it. A mutant is KILLED when the analysis reports a violation.
  local ma="$W/ma.$RANDOM.json"
  if ! python3 "$ANALYSE" "$m" > "$ma" 2>/dev/null; then
    # An unparseable mutant is caught too — the guard reds either way.
    pass; MUT_KILLED=$((MUT_KILLED + 1)); return
  fi
  local viol
  viol=$(MUT_A="$ma" MUT_CI_NAME="$CI_NAME" python3 "$MUTPRED")
  if [ -n "$viol" ]; then
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label"
    MUT_SURVIVED+=("$label")
  fi
}

# ── MUT-CONTROL rows — WITHOUT THESE THE BATTERY IS UNREADABLE ───────────────
# (i) The predicate must be EMPTY on the pristine file. This is the row whose
#     absence made every previous verdict meaningless: the predicate reported
#     `sha` at baseline, so `MUT_KILLED` counted rows that measured nothing.
_ctl=$(MUT_A="$A" MUT_CI_NAME="$CI_NAME" python3 "$MUTPRED")
if [ -z "$_ctl" ]; then pass; else
  printf 'FATAL: MUT-CONTROL — the mutant predicate reports "%s" on the UNMUTATED file.\n' "$_ctl" >&2
  printf '  Every mutation row below would score KILLED regardless of what it mutated,\n' >&2
  printf '  so the battery measures the baseline and its verdict is VOID.\n' >&2
  exit 1
fi
# (ii) A mutant that LANDS but changes nothing the guards are about must be
#      reported SURVIVING. A battery that cannot say "survived" cannot say
#      "killed" either — this is the instrument self-test for the scoring itself.
_null="$W/nullmut.yml"
sed '0,/^$/{/^$/d}' "$REL" > "$_null"          # delete the first blank line
if cmp -s "$_null" "$REL"; then
  fail "MUT-CONTROL(ii) the null mutation did not land, so the scoring self-test is vacuous"
else
  _na="$W/nullmut.json"
  if python3 "$ANALYSE" "$_null" > "$_na" 2>/dev/null; then
    _nv=$(MUT_A="$_na" MUT_CI_NAME="$CI_NAME" python3 "$MUTPRED")
    if [ -z "$_nv" ]; then pass; else
      printf 'FATAL: MUT-CONTROL(ii) — deleting a blank line was scored as a KILL ("%s").\n' "$_nv" >&2
      printf '  The scoring cannot distinguish a real defect from an inert edit.\n' >&2
      exit 1
    fi
  else
    fail "MUT-CONTROL(ii) the null mutant did not parse — the analyser is line-fragile"
  fi
fi

# G3-10 — reintroduce a bare github.sha on the wrong-image gate.
mutate "G3-10 EXPECTED_SHA reverts to bare github.sha" \
  's|EXPECTED_SHA: \${{ needs.resolve-target.outputs.head_sha }}|EXPECTED_SHA: ${{ github.sha }}|'
# G3-11 — SECOND-MEMBER ROW: a NEW job on the arm using github.sha. A guard
# scoped to the known sites cannot see this; the computed assembly can.
mutate "G3-11 a NEW workflow_run-reachable job reads github.sha" \
  's|^  verify-doppler-secrets:$|  newly-added-job:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ github.sha }}\n  verify-doppler-secrets:|'
# G3-12 — restore live-verify's push gate (would skip forever).
mutate "G3-12 live-verify regains its github.event_name == 'push' gate" \
  "s|github.event_name == 'workflow_run'\$|github.event_name == 'push'|"
# G4-15 — desync the deploy arm's workflows: entry.
mutate "G4-15 workflow_run.workflows stops naming ci.yml's name" \
  's|workflows: \["CI"\]|workflows: ["Continuous Integration"]|'
# G4-17 — remove the branches filter.
mutate "G4-17 the branches: [main] filter is removed" \
  '/^    branches: \[main\]$/d'

# ── Harness rows ─────────────────────────────────────────────────────────────
# (a) A hardcoded site list must FAIL to catch G3-11. Demonstrated positively:
#     the computed assembly finds the injected job, a fixed list of the current
#     sha sites structurally cannot.
_inject="$W/inject.yml"
sed 's|^  verify-doppler-secrets:$|  newly-added-job:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ github.sha }}\n  verify-doppler-secrets:|' "$REL" > "$_inject"
_found=$(python3 "$ANALYSE" "$_inject" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('yes' if any(s['job']=='newly-added-job' for s in d['sha_sites']) else 'no')")
if [ "$_found" = "yes" ]; then pass; else
  fail "Ha HARNESS: the computed assembly did NOT find a github.sha site in a newly added job, so mutation G3-11 proves nothing about list-vs-extraction"
fi
# (b) MUST-PASS: github.sha inside a dispatch-guarded job is permitted.
_ok="$W/ok.yml"
sed 's|^  verify-doppler-secrets:$|  dispatch-only-job:\n    if: github.event_name == '"'"'workflow_dispatch'"'"'\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ github.sha }}\n  verify-doppler-secrets:|' "$REL" > "$_ok"
_permit=$(python3 "$ANALYSE" "$_ok" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
reach=set(d['wr_reachable'])
print('violation' if any(s['job']=='dispatch-only-job' for s in d['sha_sites'] if s['job'] in reach) else 'permitted')")
if [ "$_permit" = "permitted" ]; then pass; else
  fail "Hb MUST-PASS: github.sha inside a workflow_dispatch-guarded job was flagged. The dispatch arm legitimately reads github.sha (resolve-target does exactly this), so an absolute rule reds the correct implementation"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))
# DERIVED, and NEVER LOWERED from the suite this replaces (which floored at 14):
#   1 instrument + 1 analyser + 4 G4 + 5 G3 + 10 G7 + 8 G5 + 2 G8
# + 2 dispatch-permit bounds + 5 mutants + 2 harness
# + 2 MUT-CONTROL (predicate empty at baseline; a null mutant must SURVIVE)
# + 1 extractor-scope self-test (budget.blk must not cross a job boundary)
# + 1 comment-stripper self-test (resolve.code must not be empty) = 45
# The previous itemisation summed to 40 while the suite executed 41 — a floor
# below the real count is slack an undispatched row can hide in, which is the
# same failure mode the floor exists to catch.
MIN_ROWS=45
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. The suite this replaced floored at 14; a successor may raise it, never lower it.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
if [ "$MUT_TOTAL" -lt 5 ]; then
  printf 'FAIL: mutation floor — %d mutants, at least 5 required.\n' "$MUT_TOTAL" >&2
  exit 1
fi

echo
echo "mutation battery: $MUT_KILLED/$MUT_TOTAL killed"
if [ "${#MUT_SURVIVED[@]}" -gt 0 ]; then
  printf 'surviving mutants (fixture-inadequate or equivalent — label which):\n' >&2
  printf '  - %s\n' "${MUT_SURVIVED[@]}" >&2
fi
echo "workflow-run-deploy-invariants.test.sh: $TOTAL rows, $passes passed, $fails failed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\nfailures:\n' >&2; printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
