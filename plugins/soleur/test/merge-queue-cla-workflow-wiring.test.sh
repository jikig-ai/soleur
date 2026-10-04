#!/usr/bin/env bash
# Wiring suite for .github/workflows/merge-queue-cla-synthetics.yml (#9454, review L3).
#
# The workflow holds a checks:write token under the github-actions identity (integration 15368)
# that the CLA Required ruleset trusts. Its safety is WIRING, not logic: the verify step must run
# first and must not be skippable or tolerant, the verifier must come from the DEFAULT branch,
# event data must reach the shell through env only, and the names it posts must be exactly the
# names the ruleset requires and the verifier checks. merge-queue-cla-verify.test.sh proves the
# verifier; nothing proved this wiring, so a deleted verify step, a `|| true`, a candidate
# checkout or a post-name drift left every suite green.
#
# HOW: the workflow is PARSED (PyYAML; the bare key `on` loads as boolean True) and STRUCTURED
# properties are asserted, never a grep of the file's text. The posted names, the verifier's names
# and the ruleset's names are each DERIVED from their own file (no hand-typed list) and compared.
#
# MUTATION ROWS: each mutation is applied to a COPY in a mktemp sandbox, proven to land (cmp
# against the pristine copy) and must turn the property that guards it RED. The checker is also
# run against the pristine copy first: every property must be green, and exactly NPROPS lines
# must come back, so a checker that stops reporting is not read as "all clear".
#
# CONTROLS: the verdict-owning helpers (expect_all_ok, expect_bad, mutant) are each driven once
# with an input that must fail; their failure counter must move.
# shellcheck disable=SC2016,SC2329  # sed programs and workflow expressions are literal text; mutate() callees run indirectly
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF_REL=".github/workflows/merge-queue-cla-synthetics.yml"
VERIFY_REL="scripts/merge-queue-cla-verify.sh"
CANON_REL="scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"

# Number of properties the checker reports on a healthy workflow (W1..W17).
NPROPS=17
# Exact assertion floor, re-derived from a green run.
EXPECTED_PASSES=60

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

command -v python3 >/dev/null 2>&1 || { echo "[FATAL] python3 not found" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "[FATAL] python3 has no PyYAML module" >&2; exit 2; }
for f in "$WF_REL" "$VERIFY_REL" "$CANON_REL"; do
  [[ -f "$REPO_ROOT/$f" ]] || { echo "[FATAL] $f is missing" >&2; exit 2; }
done

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

# ---- the checker (PyYAML; one `ok|bad <id> <detail>` line per property) ----------------------
CHECKER="$WORK/check_wiring.py"
cat > "$CHECKER" <<'PY'
import json
import re
import sys

import yaml

wf_path, verify_path, canon_path = sys.argv[1:4]
results = []


def rec(pid, ok, detail=""):
    results.append((pid, bool(ok), detail))


def norm(x):
    return re.sub(r"\s+", " ", str(x)).strip()


try:
    with open(wf_path) as fh:
        d = yaml.safe_load(fh)
except Exception as exc:  # unparseable workflow: every property is bad, never silently skipped
    d = None
    err = str(exc).splitlines()[0] if str(exc) else "unparseable"
if not isinstance(d, dict):
    for pid in ["W%d" % i for i in range(1, 18)]:
        rec(pid, False, "workflow did not parse to a mapping")
    for pid, ok, detail in results:
        print("%s %s %s" % ("ok" if ok else "bad", pid, detail))
    sys.exit(0)

# PyYAML (YAML 1.1) loads the bare key `on` as the boolean True.
on = d.get("on", d.get(True))
trig = set(on) if isinstance(on, (dict, list)) else ({on} if isinstance(on, str) else set())
rec("W1", trig == {"merge_group"}, "triggers=%s" % sorted(map(str, trig)))

perms = d.get("permissions")
want_perms = {"checks": "write", "pull-requests": "read", "contents": "read"}
rec("W2", perms == want_perms, "permissions=%s" % perms)

jobs = d.get("jobs") if isinstance(d.get("jobs"), dict) else {}
job = None
if len(jobs) == 1:
    job = next(iter(jobs.values()))
steps = job.get("steps") if isinstance(job, dict) and isinstance(job.get("steps"), list) else []


def run_of(step):
    return step.get("run") if isinstance(step, dict) and isinstance(step.get("run"), str) else ""


def idx_where(pred):
    return [i for i, s in enumerate(steps) if isinstance(s, dict) and pred(s)]


checkout_i = idx_where(lambda s: str(s.get("uses", "")).startswith("actions/checkout@"))
verify_i = idx_where(lambda s: "merge-queue-cla-verify.sh" in run_of(s))
success_i = idx_where(lambda s: re.search(r"conclusion=success\b", run_of(s)) is not None)
failure_i = idx_where(lambda s: re.search(r"conclusion=failure\b", run_of(s)) is not None)
one = lambda l: l[0] if len(l) == 1 else None
ck, vf, sc, fl = one(checkout_i), one(verify_i), one(success_i), one(failure_i)


def has_coe(s):
    return "continue-on-error" in s


# W3: default-branch checkout, no persisted credentials, before the verifier runs.
if ck is None:
    rec("W3", False, "expected exactly one checkout step, found %d" % len(checkout_i))
else:
    w = steps[ck].get("with") or {}
    ref_ok = norm(w.get("ref", "")) == "${{ github.event.repository.default_branch }}"
    pc_ok = w.get("persist-credentials") is False
    ord_ok = vf is not None and ck < vf
    rec("W3", ref_ok and pc_ok and ord_ok and not has_coe(steps[ck]),
        "ref_ok=%s persist_false=%s before_verify=%s" % (ref_ok, pc_ok, ord_ok))

# W4: the verifier step runs the script, tolerates nothing, and cannot be skipped.
if vf is None:
    rec("W4", False, "expected exactly one verify step, found %d" % len(verify_i))
else:
    s = steps[vf]
    cmd = norm(run_of(s))
    rec("W4", cmd == "bash scripts/merge-queue-cla-verify.sh" and not has_coe(s) and "if" not in s
        and "||" not in cmd and "|" not in cmd and ";" not in cmd,
        "run=%r continue_on_error=%s if=%s" % (cmd, has_coe(s), s.get("if")))


def loops(run):
    return [(m.group(1), m.group(2).split())
            for m in re.finditer(r"\bfor\s+(\w+)\s+in\s+([^;\n]+?)\s*;\s*do\b", run)]


def post_shape(step, conclusion):
    """(ok, names, detail) for a posting step: one loop, the loop variable is the name, the
    candidate head_sha comes from env, status completed, the expected conclusion."""
    run = run_of(step)
    ls = loops(run)
    if len(ls) != 1:
        return False, [], "expected one for-loop, found %d" % len(ls)
    var, names = ls[0]
    name_ok = re.search(r'-f\s+name="?\$\{?%s\}?"?(\s|\\|$)' % re.escape(var), run) is not None
    sha_ok = re.search(r'-f\s+head_sha="?\$\{?HEAD_SHA\}?"?(\s|\\|$)', run) is not None
    status_ok = re.search(r"-f\s+status=completed\b", run) is not None
    concl_ok = re.search(r"-f\s+conclusion=%s\b" % conclusion, run) is not None
    ep_ok = 'gh api "repos/${REPO}/check-runs"' in run
    one_concl = len(re.findall(r"conclusion=", run)) == 1
    ok = name_ok and sha_ok and status_ok and concl_ok and ep_ok and one_concl
    return ok, names, "name_is_loop_var=%s head_sha_env=%s status=%s conclusion=%s endpoint=%s single_conclusion=%s" % (
        name_ok, sha_ok, status_ok, concl_ok, ep_ok, one_concl)


# W5: the success step runs after verify, unconditionally (default success()), tolerates nothing.
succ_names = []
if sc is None:
    rec("W5", False, "expected exactly one conclusion=success step, found %d" % len(success_i))
else:
    s = steps[sc]
    shape_ok, succ_names, detail = post_shape(s, "success")
    after = vf is not None and sc > vf
    skippable = "if" in s and norm(s["if"]) not in ("success()", "${{ success() }}")
    rec("W5", shape_ok and after and not skippable and not has_coe(s),
        "%s after_verify=%s skippable=%s continue_on_error=%s" % (detail, after, skippable, has_coe(s)))

# W6: event data enters through env, from the merge_group payload.
env = job.get("env") if isinstance(job, dict) and isinstance(job.get("env"), dict) else {}
want_env = {
    "GH_TOKEN": "${{ github.token }}",
    "REPO": "${{ github.repository }}",
    "HEAD_SHA": "${{ github.event.merge_group.head_sha }}",
    "HEAD_REF": "${{ github.event.merge_group.head_ref }}",
    "BASE_REF": "${{ github.event.merge_group.base_ref }}",
}
bad_env = sorted(k for k, v in want_env.items() if norm(env.get(k, "")) != v)
rec("W6", not bad_env, "wrong or missing env: %s" % bad_env)

# W7: no `${{ }}` interpolation inside any run: block (script-injection surface).
interp = [str(s.get("name", i)) for i, s in enumerate(steps) if "${{" in run_of(s)]
rec("W7", not interp, "run blocks with ${{ }}: %s" % interp)

# W8: posted names (success step, failure step) == the ruleset's names == the verifier's names.
canon = set(item["context"] for item in json.load(open(canon_path)))
vtext = open(verify_path).read()
vloops = re.findall(r"^\s*for\s+ctx\s+in\s+([^;\n]+?)\s*;\s*do\b", vtext, re.M)
verify_names = set(vloops[0].split()) if len(vloops) == 1 else set()
fail_names = []
if fl is not None:
    fail_names = post_shape(steps[fl], "failure")[1]
rec("W8", len(vloops) == 1 and canon and set(succ_names) == canon and set(fail_names) == canon
    and verify_names == canon and len(succ_names) == len(set(succ_names)),
    "success=%s failure=%s ruleset=%s verifier=%s" % (sorted(succ_names), sorted(fail_names),
                                                       sorted(canon), sorted(verify_names)))

# W9: the failure step: after verify, runs only on failure, posts failure on the same names.
if fl is None:
    rec("W9", False, "expected exactly one conclusion=failure step, found %d" % len(failure_i))
else:
    s = steps[fl]
    shape_ok, _, detail = post_shape(s, "failure")
    cond = norm(s.get("if", ""))
    rec("W9", shape_ok and vf is not None and fl > vf and cond in ("failure()", "${{ failure() }}")
        and not has_coe(s) and "conclusion=success" not in run_of(s),
        "%s if=%r after_verify=%s" % (detail, cond, vf is not None and fl > vf))

# W10: one job, no job-level if/needs/continue-on-error/permissions, and the failure step is the
# ONLY step with an `if`.
if job is None:
    rec("W10", False, "expected exactly one job, found %d" % len(jobs))
else:
    job_bad = sorted(k for k in ("if", "needs", "continue-on-error", "permissions") if k in job)
    step_ifs = [i for i, s in enumerate(steps) if isinstance(s, dict) and "if" in s]
    rec("W10", not job_bad and step_ifs == ([fl] if fl is not None else []),
        "job keys %s step_ifs=%s failure_step=%s" % (job_bad, step_ifs, fl))

# W11: the verifier is wired once: names derivable from the script, single loop.
rec("W11", len(vloops) == 1, "verifier has %d `for ctx in` loops" % len(vloops))

# W12: ordering checkout < verify < success < failure, all present.
order = [ck, vf, sc, fl]
rec("W12", None not in order and order == sorted(order), "indices checkout,verify,success,failure=%s" % order)

# W13: the step list is PINNED (checkout, verify, success post, failure post: nothing between the
# default-branch checkout and verify can fetch candidate scripts) and every step key is whitelisted:
# no `shell:` (verify could be a no-op), `working-directory`, `timeout-minutes`, `continue-on-error`.
STEP_KEYS = {"name", "id", "uses", "with", "run", "env", "if"}
step_shape = [("uses" if "uses" in s else "run") if isinstance(s, dict) else "?" for s in steps]
extra_keys = sorted({k for s in steps if isinstance(s, dict) for k in s if k not in STEP_KEYS})
rec("W13", len(steps) == 4 and step_shape == ["uses", "run", "run", "run"] and ck == 0 and vf == 1
    and sc == 2 and fl == 3 and not extra_keys,
    "steps=%d shape=%s non-whitelisted step keys=%s" % (len(steps), step_shape, extra_keys))

# W14: env is EXACT. Job env is the five pinned keys and nothing else (no PATH, no extra);
# there is no workflow-level env; the only step-level env is on the failure step and is exactly
# {VERIFY_REASON, VERIFY_OUTCOME}; no step re-defines HEAD_SHA/BASE_REF/HEAD_REF/REPO.
want_fail_env = {"VERIFY_REASON": "${{ steps.verify.outputs.reason }}",
                 "VERIFY_OUTCOME": "${{ steps.verify.outcome }}"}
step_envs = {i: s.get("env") for i, s in enumerate(steps) if isinstance(s, dict) and "env" in s}
fail_env = step_envs.get(fl) if fl is not None else None
shadow = sorted({k for e in step_envs.values() if isinstance(e, dict) for k in e
                 if k in ("HEAD_SHA", "BASE_REF", "HEAD_REF", "REPO", "GH_TOKEN", "PATH")})
job_env_exact = set(env) == set(want_env)
rec("W14", job_env_exact and "env" not in d and set(step_envs) <= ({fl} if fl is not None else set())
    and (fail_env is None or {k: norm(v) for k, v in fail_env.items()} == want_fail_env) and not shadow
    and fail_env is not None,
    "job env keys=%s workflow env=%s step env on steps=%s shadowed=%s" % (
        sorted(env), "env" in d, sorted(step_envs), shadow))

# W15: the checkout takes exactly {ref, persist-credentials, sparse-checkout, sparse-checkout-cone-mode}:
# no `repository:` (a fork), no `path:`, no extra input that redirects what is checked out.
want_with = {"ref", "persist-credentials", "sparse-checkout", "sparse-checkout-cone-mode"}
cw = (steps[ck].get("with") or {}) if ck is not None else {}
rec("W15", ck is not None and set(cw) == want_with and norm(cw.get("sparse-checkout", "")) == "scripts/merge-queue-cla-verify.sh"
    and cw.get("sparse-checkout-cone-mode") is False,
    "checkout with keys=%s sparse=%r" % (sorted(cw), cw.get("sparse-checkout")))

# W16: job and workflow carry no key that changes where or how the steps run.
job_allowed = {"runs-on", "timeout-minutes", "env", "steps"}
job_extra = sorted(k for k in (job or {}) if k not in job_allowed)
wf_allowed = {"name", "on", True, "permissions", "jobs"}
wf_extra = sorted(str(k) for k in d if k not in wf_allowed)
rec("W16", job is not None and not job_extra and not wf_extra and (job or {}).get("runs-on") == "ubuntu-latest",
    "job keys outside the whitelist=%s workflow keys outside the whitelist=%s runs-on=%r" % (
        job_extra, wf_extra, (job or {}).get("runs-on")))

# W17: the failure title names the right reason: it keys off steps.verify.outcome, and the old wording
# that blames the verify step when verify PASSED is gone.
frun = run_of(steps[fl]) if fl is not None else ""
uses_outcome = (re.search(r'"\$\{VERIFY_OUTCOME:-\}"\s*==\s*"success"', frun) is not None
                and re.search(r'"\$\{VERIFY_OUTCOME:-\}"\s*==\s*"failure"', frun) is not None)
rec("W17", fl is not None and uses_outcome and "posting the verified result failed" in frun
    and "before the verify step" not in frun,
    "uses VERIFY_OUTCOME=%s success wording=%s old wording absent=%s" % (
        uses_outcome, "posting the verified result failed" in frun, "before the verify step" not in frun))

for pid, ok, detail in results:
    print("%s %s %s" % ("ok" if ok else "bad", pid, detail))
PY
chmod +x "$CHECKER" || exit 2

# ---- harness -----------------------------------------------------------------------------------
CHK=""
# run_check <wf> <verify-script> <canonical-json> : CHK = the checker's lines (empty when it crashed)
run_check() {
  local wf="$1" vs="$2" cj="$3"
  CHK="$(python3 "$CHECKER" "$wf" "$vs" "$cj" 2>/dev/null)" || CHK=""
}

# props_ok / props_bad: how many `ok` / `bad` lines the checker reported
count_prefix() { printf '%s\n' "$CHK" | grep -c -E -- "^$1 " || true; }

# expect_all_ok <label>: exactly NPROPS lines, every one ok. A crashed or silent checker is RED.
expect_all_ok() {
  local label="$1" nok nbad
  nok="$(count_prefix ok)"; nbad="$(count_prefix bad)"
  if [[ "$nok" -eq "$NPROPS" && "$nbad" -eq 0 ]]; then
    pass "$label"
  else
    fail "$label (ok=$nok bad=$nbad, wanted ok=$NPROPS bad=0)"
    printf '%s\n' "$CHK" | grep -E -- '^bad ' | head -n 6 >&2
  fi
}

# expect_bad <label> <property-id>: that property is `bad` in the checker output.
expect_bad() {
  local label="$1" pid="$2"
  if printf '%s\n' "$CHK" | grep -E -- "^bad ${pid} " >/dev/null; then
    pass "$label"
  else
    fail "$label (property ${pid} stayed green)"
    printf '%s\n' "$CHK" | head -n 14 >&2
  fi
}

PRISTINE="$WORK/pristine"; assert_fixture_dir "$PRISTINE"
mkdir -p "$PRISTINE/.github/workflows" "$PRISTINE/scripts" || exit 2
cp "$REPO_ROOT/$WF_REL" "$PRISTINE/$WF_REL" || exit 2
cp "$REPO_ROOT/$VERIFY_REL" "$PRISTINE/$VERIFY_REL" || exit 2
cp "$REPO_ROOT/$CANON_REL" "$PRISTINE/$CANON_REL" || exit 2

echo "== merge-queue CLA workflow wiring =="
echo "-- the real workflow"
run_check "$REPO_ROOT/$WF_REL" "$REPO_ROOT/$VERIFY_REL" "$REPO_ROOT/$CANON_REL"
expect_all_ok "real workflow: all $NPROPS wiring properties hold"
run_check "$PRISTINE/$WF_REL" "$PRISTINE/$VERIFY_REL" "$PRISTINE/$CANON_REL"
expect_all_ok "control: the pristine copy agrees with the live tree"

echo "-- mutation rows (each lands, then must turn its property RED)"
MUT="$WORK/mut"; assert_fixture_dir "$MUT"; mkdir -p "$MUT" || exit 2
CASE_N=0

# mutant <id> <property> <target: wf|verify|canon> <sh-edit-command...>
# The edit runs against ONE file of a fresh copy of the pristine trio; it must change that file.
mutant() {
  local id="$1" prop="$2" target="$3"; shift 3
  CASE_N=$((CASE_N + 1))
  local d="$MUT/m.$CASE_N"; assert_fixture_dir "$d"
  mkdir -p "$d/.github/workflows" "$d/scripts" || exit 2
  cp "$PRISTINE/$WF_REL" "$d/$WF_REL" || exit 2
  cp "$PRISTINE/$VERIFY_REL" "$d/$VERIFY_REL" || exit 2
  cp "$PRISTINE/$CANON_REL" "$d/$CANON_REL" || exit 2
  local rel
  case "$target" in
    wf) rel="$WF_REL" ;;
    verify) rel="$VERIFY_REL" ;;
    canon) rel="$CANON_REL" ;;
    *) fail "mutant $id: unknown target $target"; return ;;
  esac
  "$@" "$d/$rel" || { fail "mutant $id: the edit command failed"; return; }
  if cmp -s "$PRISTINE/$rel" "$d/$rel"; then fail "mutant $id: mutation did not land"; return; fi
  run_check "$d/$WF_REL" "$d/$VERIFY_REL" "$d/$CANON_REL"
  expect_bad "mutant $id turns $prop RED" "$prop"
}

sedi() { local expr="$1"; shift; sed -i "$expr" "$@"; }
# first occurrence only (GNU sed 0,/re/)
sed_first() { local re="$1" rep="$2"; shift 2; sed -i "0,/${re}/s//${rep}/" "$@"; }

mutant coe-verify    W4 wf sedi "/id: verify/a\\        continue-on-error: true"
mutant or-true       W4 wf sedi 's#^\(        run: bash scripts/merge-queue-cla-verify.sh\)$#\1 || true#'
mutant verify-gone   W4 wf sedi '/id: verify/,/run: bash scripts\/merge-queue-cla-verify.sh/d'
mutant verify-if     W4 wf sedi "/id: verify/a\\        if: github.event_name == 'merge_group'"
mutant no-ref        W3 wf sedi '/ref: \${{ github.event.repository.default_branch }}/d'
mutant cand-ref      W3 wf sedi 's#ref: \${{ github.event.repository.default_branch }}#ref: ${{ github.sha }}#'
mutant persist       W3 wf sedi '/persist-credentials: false/d'
mutant base-env      W6 wf sedi '/BASE_REF: /d'
mutant head-ref-env  W6 wf sedi 's#HEAD_REF: \${{ github.event.merge_group.head_ref }}#HEAD_REF: ${{ github.head_ref }}#'
mutant inline-event  W7 wf sedi 's#bash scripts/merge-queue-cla-verify.sh#echo ${{ github.event.merge_group.head_ref }}; bash scripts/merge-queue-cla-verify.sh#'
mutant sha-success   W5 wf sed_first 'head_sha="\$HEAD_SHA"' 'head_sha="$HEAD_REF"'
mutant neutral       W5 wf sed_first 'conclusion=success' 'conclusion=neutral'
mutant literal-name  W5 wf sed_first '-f name="\$check"' '-f name=cla-check'
mutant post-if-false W5 wf sedi "/name: Re-post cla-check/a\\        if: false"
mutant post-coe      W5 wf sedi "/name: Re-post cla-check/a\\        continue-on-error: true"
mutant loop-short    W8 wf sed_first 'for check in cla-check cla-evidence; do' 'for check in cla-check; do'
mutant loop-extra    W8 wf sed_first 'for check in cla-check cla-evidence; do' 'for check in cla-check cla-evidence cla-extra; do'
mutant verify-names  W8 verify sedi 's/for ctx in cla-check cla-evidence; do/for ctx in cla-check; do/'
mutant canon-names   W8 canon sedi 's/"cla-evidence"/"cla-evidence-renamed"/'
mutant perm-write    W2 wf sedi 's/^  contents: read$/  contents: write/'
mutant trig-extra    W1 wf sedi 's/^  merge_group:$/  merge_group:\n  pull_request_target:/'
mutant job-needs     W10 wf sedi '/^    runs-on: ubuntu-latest$/a\    needs: other'
mutant job-if        W10 wf sedi "/^    runs-on: ubuntu-latest\$/a\\    if: github.event_name == 'merge_group'"
# the failure-post path (L2)
mutant fail-gone     W9 wf sedi '/name: Report cla-check + cla-evidence as failed/,$d'
mutant fail-noif     W9 wf sedi '/^        if: failure()$/d'
mutant fail-neutral  W9 wf sedi 's/conclusion=failure/conclusion=neutral/'
mutant fail-success  W9 wf sedi 's/conclusion=failure/conclusion=success/'
mutant fail-always   W9 wf sedi 's/^        if: failure()$/        if: always()/'
mutant fail-sha      W9 wf sedi '/name: Report cla-check + cla-evidence as failed/,$s#head_sha="\$HEAD_SHA"#head_sha="$HEAD_REF"#'
# the failure step moved BEFORE the success step (a reorder, not a text edit)
swap_post_steps() {
  python3 - "$1" <<'PYSWAP'
import sys
p = sys.argv[1]
t = open(p).read()
a = t.index("      - name: Re-post cla-check")
b = t.index("      # Fail visibly:")
open(p, "w").write(t[:a] + t[b:] + "\n" + t[a:b].rstrip("\n") + "\n")
PYSWAP
}
mutant fail-order    W12 wf swap_post_steps

control_fails() {
  local label="$1" want_msg="$2"; shift 2
  local p0="$passes" f0="$fails" n0="${#FAILED[@]}" moved=0 msg_ok=1
  "$@" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  if [[ -n "$want_msg" ]]; then
    [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] || msg_ok=0
  fi
  passes="$p0"; fails="$f0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: $label fails on an input that must fail"
  else
    fail "control: $label did not record a failure on an input that must fail"
  fi
}

# ---- F5: ABSENCE of other keys (listed keys are not enough: an extra key can override them) --------
# pyedit <old> <new> <file>: literal, first-occurrence replacement (multi-line safe, unlike sed a\).
pyedit() {
  OLD="$1" NEW="$2" python3 - "$3" <<'PYEDIT'
import os, sys
p = sys.argv[1]
t = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in t:
    sys.exit(1)
open(p, "w").write(t.replace(old, new, 1))
PYEDIT
}
POST_HDR='      - name: Re-post cla-check + cla-evidence on the merge-queue candidate
        run: |'
VERIFY_HDR='        id: verify
        run: bash scripts/merge-queue-cla-verify.sh'
mutant step-env-sha   W14 wf pyedit "$POST_HDR" '      - name: Re-post cla-check + cla-evidence on the merge-queue candidate
        env:
          HEAD_SHA: ${{ github.event.merge_group.base_sha }}
        run: |'
mutant step-env-refs  W14 wf pyedit "$VERIFY_HDR" '        id: verify
        env:
          BASE_REF: refs/heads/main
          HEAD_REF: gh-readonly-queue/main/pr-1-x
        run: bash scripts/merge-queue-cla-verify.sh'
mutant step-env-repo  W14 wf pyedit "$POST_HDR" '      - name: Re-post cla-check + cla-evidence on the merge-queue candidate
        env:
          REPO: evil/fork
        run: |'
mutant job-env-path   W14 wf pyedit '      BASE_REF: ${{ github.event.merge_group.base_ref }}' '      BASE_REF: ${{ github.event.merge_group.base_ref }}
      PATH: /tmp/evil:/usr/bin'
mutant wf-env         W14 wf pyedit 'permissions:
  checks: write' 'env:
  PATH: /tmp/evil:/usr/bin

permissions:
  checks: write'
mutant fail-env-extra W14 wf pyedit '          VERIFY_OUTCOME: ${{ steps.verify.outcome }}' '          VERIFY_OUTCOME: ${{ steps.verify.outcome }}
          HEAD_SHA: ${{ github.sha }}'
mutant extra-step     W13 wf pyedit '      - name: Verify the PR head' '      - name: Fetch candidate scripts
        run: git fetch origin "$HEAD_REF" && git checkout FETCH_HEAD -- scripts/

      - name: Verify the PR head'
mutant verify-shell   W13 wf pyedit "$VERIFY_HDR" '        id: verify
        shell: echo {0}
        run: bash scripts/merge-queue-cla-verify.sh'
mutant verify-workdir W13 wf pyedit "$VERIFY_HDR" '        id: verify
        working-directory: /tmp
        run: bash scripts/merge-queue-cla-verify.sh'
mutant step-timeout   W13 wf pyedit "$VERIFY_HDR" '        id: verify
        timeout-minutes: 1
        run: bash scripts/merge-queue-cla-verify.sh'
mutant checkout-repo  W15 wf pyedit '          persist-credentials: false' '          repository: evil/fork
          persist-credentials: false'
mutant checkout-path  W15 wf pyedit '          persist-credentials: false' '          path: elsewhere
          persist-credentials: false'
mutant sparse-widen   W15 wf pyedit 'sparse-checkout: scripts/merge-queue-cla-verify.sh' 'sparse-checkout: scripts'
mutant job-container  W16 wf pyedit '    timeout-minutes: 5' '    timeout-minutes: 5
    container: evil/image:latest'
mutant job-defaults   W16 wf pyedit '    timeout-minutes: 5' '    timeout-minutes: 5
    defaults:
      run:
        shell: echo {0}'
mutant wf-defaults    W16 wf pyedit 'jobs:
  cla-synthetics:' 'defaults:
  run:
    shell: echo {0}

jobs:
  cla-synthetics:'
# F7: the failure title must not blame the verify step when verify passed
mutant fail-old-text  W17 wf pyedit 'reason="verification passed but posting the verified result failed"' 'reason="verification did not complete before the verify step"'
mutant fail-no-outcome W17 wf pyedit '[[ "${VERIFY_OUTCOME:-}" == "success" ]]' '[[ "${VERIFY_OUTCOMES:-}" == "success" ]]'

# ---- F7 executed: the failure step's title for each verify outcome, run against a stub gh -----------
echo "-- executed: failure-step title per verify outcome"
FBIN="$WORK/fbin"; assert_fixture_dir "$FBIN"; mkdir -p "$FBIN" || exit 2
cat > "$FBIN/gh" <<'STUB'
#!/usr/bin/env bash
# stub gh: records every `-f output[title]=...` it is given
for a in "$@"; do case "$a" in output\[title\]=*) printf '%s\n' "${a#output\[title\]=}" >> "$GH_TITLES" ;; esac; done
exit 0
STUB
chmod +x "$FBIN/gh"
# fail_titles <workflow-file> <reason> <outcome>: run the failure step's run body; titles to $WORK/titles
fail_titles() {
  local wf="$1" reason="$2" outcome="$3" body="$WORK/fail-body.sh"
  python3 - "$wf" "$body" <<'PYBODY' || return 1
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for st in next(iter(d["jobs"].values()))["steps"]:
    if "conclusion=failure" in str(st.get("run", "")):
        open(sys.argv[2], "w").write(st["run"]); sys.exit(0)
sys.exit(1)
PYBODY
  rm -f "$WORK/titles"
  env -i PATH="$FBIN:/usr/local/bin:/usr/bin:/bin" GH_TITLES="$WORK/titles" REPO=o/r HEAD_SHA=abc \
    VERIFY_REASON="$reason" VERIFY_OUTCOME="$outcome" bash "$body" >/dev/null 2>&1
}
# fail_title_row <label> <workflow> <reason> <outcome> <must-contain> <must-not-contain>
fail_title_row() {
  local label="$1" wf="$2" reason="$3" outcome="$4" want="$5" unwant="$6" n t
  if ! fail_titles "$wf" "$reason" "$outcome"; then fail "$label (the failure step did not run)"; return; fi
  n="$(grep -c . "$WORK/titles" 2>/dev/null || true)"; t="$(head -n 1 "$WORK/titles" 2>/dev/null || true)"
  if [[ "$n" -eq 2 && "$t" == *"$want"* && ( -z "$unwant" || "$t" != *"$unwant"* ) ]]; then
    pass "$label"
  else
    fail "$label (titles=$n first='$t', wanted '$want' and not '$unwant')"
  fi
}
WFP="$PRISTINE/$WF_REL"
fail_title_row "title: verify passed, success post failed -> says posting failed, not 'before the verify step'" "$WFP" "" success "posting the verified result failed" "before the verify step"
fail_title_row "title: verify failed without a recorded reason -> says so" "$WFP" "" failure "the verify step failed without a recorded reason" "posting the verified"
fail_title_row "title: checkout failed before verify (outcome skipped) -> names the earlier step" "$WFP" "" skipped "a step before verification failed" "posting the verified"
fail_title_row "title: verify recorded a reason -> that reason wins over the outcome" "$WFP" "the PR head cla-check is not green" failure "the PR head cla-check is not green" "posting the verified"
# the same row against a reverted workflow must go red (the row is not agreeing with anything)
REVERTED="$WORK/reverted.yml"; assert_fixture_dir "$REVERTED"
cp "$WFP" "$REVERTED"
pyedit 'reason="verification passed but posting the verified result failed"' 'reason="verification did not complete before the verify step"' "$REVERTED" || exit 2
control_fails "fail_title_row (a reverted wording that blames the verify step)" "before the verify step" \
  fail_title_row "ctl-title" "$REVERTED" "" success "posting the verified result failed" "before the verify step"

# ---- controls: the verdict-owning helpers must fail on an input that must fail -------------------
echo "-- controls: expect_all_ok / expect_bad / mutant fail on an input that must fail"
# a checker that crashed (empty output) must not read as green
CHK=""
control_fails "expect_all_ok (silent checker)" "ctl-silent" expect_all_ok "ctl-silent"
# an unparseable workflow: every property is bad
garbage="$WORK/garbage.yml"; assert_fixture_dir "$garbage"
printf 'jobs: [unclosed\n' > "$garbage"
run_check "$garbage" "$PRISTINE/$VERIFY_REL" "$PRISTINE/$CANON_REL"
control_fails "expect_all_ok (unparseable workflow)" "ctl-garbage" expect_all_ok "ctl-garbage"
# a property that is green must not satisfy expect_bad
run_check "$PRISTINE/$WF_REL" "$PRISTINE/$VERIFY_REL" "$PRISTINE/$CANON_REL"
control_fails "expect_bad (property stayed green)" "ctl-green" expect_bad "ctl-green" W4
# mutant(): a landed mutation that breaks nothing, and one that does not land
control_fails "mutant() (landed mutation that breaks nothing)" "stayed green" \
  mutant ctl-harmless W4 wf sedi '$a # harmless trailing comment'
control_fails "mutant() (mutation that does not land)" "did not land" \
  mutant ctl-noland W4 wf sedi 's/^NO_SUCH_LINE_ANYWHERE$/x/'

echo
echo "=== merge-queue CLA workflow wiring: $passes passed, $fails failed ==="
# Exact assertion floor (printf + exit): a deleted row or a neutered helper changes the count.
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf 'FAIL: %s assertions passed, the floor is exactly %s\n' "$passes" "$EXPECTED_PASSES" >&2
  exit 1
fi
if [[ "$fails" -ne 0 ]]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
