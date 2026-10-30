#!/usr/bin/env bash
# Pins the npm OIDC trusted-publishing wiring in .github/workflows/npm-publish.yml.
#
# WHY THIS EXISTS. #11585: the `npm Publish` leg failed E404 on every merge for
# ~30 hours while the release leg stayed green. The failure class was a
# long-lived NPM_TOKEN that expired (npm masks publish-authz failures as 404 on
# PUT to an existing scoped package). The fix replaces token auth with OIDC
# trusted publishing: `id-token: write` on the publish job, `npm@^11` in the job
# (the >= 11.5.1 trusted-publishing floor; Node 22 bundles 10.x), and NO
# credential wiring (`NODE_AUTH_TOKEN` env, `registry-url` `with:` — setup-node
# writes `//registry.npmjs.org/:_authToken=…` into .npmrc, and a stale
# _authToken line can mask OIDC auth selection: npm/cli#8976). A revert to any
# of those re-deads the leg silently until the next release, so the wiring is
# pinned here — the same PR-visible surface as the workflow itself.
#
# ASSERTION CONVENTION (cq-assert-anchor-not-bare-token): every check reads a
# field parsed out of yaml.safe_load — YAML comments cannot survive the parse,
# so a comment quoting `id-token` or `npm@^11` cannot satisfy a row. `run:`
# block scalars DO carry `#` lines through safe_load, so run bodies are
# comment-stripped before matching.
#
# VACUITY IS A HARD FAILURE. A workflow whose `jobs.publish` is absent, or
# parses to a non-map, reports VIOLATION and exits non-zero — never "0 publish
# jobs checked" green.
#
# Run: bash plugins/soleur/test/npm-publish-oidc.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Reachable: `cd` failing under `set -uo pipefail` (no -e) leaves REPO_ROOT
# empty and every path below silently targets the CALLER's tree.
: "${REPO_ROOT:?repo root resolved empty; assertions would target the calling tree}"
WF="$REPO_ROOT/.github/workflows/npm-publish.yml"

export TMPDIR="${TMPDIR:-/var/tmp}"
PASS=0
FAIL=0
CASES=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

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
SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

[[ -f "$WF" ]] || { echo "FATAL: missing $WF"; exit 2; }
command -v python3 >/dev/null || { echo "FATAL: python3 required"; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: pyyaml required"; exit 2; }

echo "=== npm-publish OIDC wiring ==="

# wiring_probe <workflow-file> <member|all>
#   member: `id-token` | `no-cred-wiring` | `npm11-step` | `npm-publish-retained` | `all`
#   exit 0 when the member (or every member, for `all`) holds; prints one
#   `VIOLATION: <member>` line per failure. `all` is the mutation-battery
#   predicate — a file failing ANY member is RED.
#
# run bodies are comment-stripped inside the probe: a `# npm install -g npm@^11`
# line inside a `run:` scalar cannot satisfy the CLI-floor member.
wiring_probe() {
  python3 - "$1" "$2" <<'PYG'
import re, sys, yaml

path, member = sys.argv[1], sys.argv[2]
violations = []
try:
    doc = yaml.safe_load(open(path))
except Exception as exc:
    sys.stderr.write("VIOLATION: workflow does not parse (%s)\n" % exc)
    raise SystemExit(1)

jobs = doc.get("jobs") if isinstance(doc, dict) else None
if not isinstance(jobs, dict):
    sys.stderr.write("VIOLATION: no jobs map\n")
    raise SystemExit(1)

pub = jobs.get("publish")
if not isinstance(pub, dict):
    # Vacuous dispatch is RED by construction: an absent or non-map publish job
    # leaves nothing to assert over, and nothing asserted is never green.
    sys.stderr.write("VIOLATION: jobs.publish missing or not a map\n")
    raise SystemExit(1)

want = lambda m: member in ("all", m)

if want("id-token"):
    perms = pub.get("permissions")
    if not isinstance(perms, dict) or perms.get("id-token") != "write":
        violations.append("id-token: jobs.publish.permissions lacks `id-token: write`")

steps = pub.get("steps")
if not isinstance(steps, list):
    steps = []

def run_body(st):
    if not isinstance(st, dict):
        return ""
    body = st.get("run")
    if body is None:
        return ""
    return "\n".join(
        l for l in str(body).split("\n") if not l.lstrip().startswith("#")
    )

if want("no-cred-wiring"):
    key_pat = re.compile(r"AUTH_?TOKEN|_authToken", re.IGNORECASE)
    val_pat = re.compile(r"_authToken|secrets\.NPM_TOKEN")
    for i, st in enumerate(steps):
        if not isinstance(st, dict):
            continue
        env = st.get("env")
        if isinstance(env, dict):
            for k, v in env.items():
                if key_pat.search(str(k)) or val_pat.search(str(v)):
                    violations.append(
                        "no-cred-wiring: step %d env carries credential wiring (%s)" % (i, k))
        with_ = st.get("with")
        if isinstance(with_, dict) and "registry-url" in with_:
            violations.append(
                "no-cred-wiring: step %d `with:` carries registry-url "
                "(writes .npmrc _authToken, masks OIDC auth)" % i)

run_bodies = "\n".join(run_body(st) for st in steps)
if want("npm11-step"):
    if not re.search(r"npm\s+install\s+-g\s+npm@\^11\b", run_bodies):
        violations.append("npm11-step: no step installs npm@^11 (>= 11.5.1 floor)")
if want("npm-publish-retained"):
    if not re.search(r"\bnpm\s+publish\b", run_bodies):
        violations.append("npm-publish-retained: no step invokes `npm publish`")

if violations:
    for v in violations:
        sys.stderr.write("VIOLATION: %s\n" % v)
    raise SystemExit(1)
raise SystemExit(0)
PYG
}

# ---------------------------------------------------------------------------
# Member rows — each contract member reported individually against the real file.
# ---------------------------------------------------------------------------
for m in id-token no-cred-wiring npm11-step npm-publish-retained; do
  CASES=$((CASES + 1))
  rc=0; out="$(wiring_probe "$WF" "$m" 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "member $m holds in npm-publish.yml"
  else
    fail "member $m violated in npm-publish.yml: $out"
  fi
done

# Whole-guard predicate over the real file — the form every mutation row below
# drives red.
CASES=$((CASES + 1))
rc=0; out="$(wiring_probe "$WF" all 2>&1)" || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "whole-guard predicate green on npm-publish.yml"
else
  fail "whole-guard predicate red on npm-publish.yml: $out"
fi

# ---------------------------------------------------------------------------
# Mutation battery (Guard Contract matrix). Each row applies ONE edit to a copy
# of the parsed workflow, re-dumps it, and drives the whole-guard predicate to
# its declared verdict. A row whose verdict is unexpected fails LOUDLY — a guard
# that cannot be driven red is vacuous.
# ---------------------------------------------------------------------------
mutate() { # mutate <variant> <out-file>
  python3 - "$WF" "$1" "$2" <<'PYM'
import sys, yaml

src, variant, out = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(src))
pub = doc["jobs"].get("publish")

if variant == "m1":  # remove id-token: write
    pub["permissions"].pop("id-token", None)
elif variant == "m2":  # re-add NODE_AUTH_TOKEN to a publish step env
    target = None
    for st in pub.get("steps", []):
        if "npm publish" in str(st.get("run", "")):
            target = st
            break
    if target is None:
        target = pub["steps"][-1]
    target.setdefault("env", {})["NODE_AUTH_TOKEN"] = "${{ secrets.NPM_TOKEN }}"
elif variant == "m3":  # file lacks jobs.publish entirely (vacuous dispatch)
    doc["jobs"]["release"] = doc["jobs"].pop("publish")
elif variant == "m4":  # delete the npm@^11 freshness step
    pub["steps"] = [
        st for st in pub["steps"]
        if "npm install -g npm@^11" not in str(st.get("run", ""))
    ]
elif variant == "m5":  # jobs.publish parses to a non-map
    doc["jobs"]["publish"] = "not-a-map"
elif variant == "m6":  # compliant superset: extra unrelated permission
    pub["permissions"]["issues"] = "read"
else:
    sys.stderr.write("unknown variant %s\n" % variant)
    raise SystemExit(2)

yaml.safe_dump(doc, open(out, "w"), default_flow_style=False, sort_keys=False)
PYM
}

expect_red() { # expect_red <label> <file>
  CASES=$((CASES + 1))
  rc=0; wiring_probe "$2" all >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "mutation caught: $1"
  else
    fail "mutation SURVIVED: $1 left the guard green"
  fi
}

expect_pass() { # expect_pass <label> <file>
  CASES=$((CASES + 1))
  rc=0; wiring_probe "$2" all >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "compliant superset accepted: $1"
  else
    fail "compliant superset REJECTED: $1 reddened the guard"
  fi
}

for v in m1 m2 m3 m4 m5 m6; do
  f="$SANDBOX/mutated-$v.yml"
  assert_fixture_dir "$(dirname "$f")"
  rc=0; mutate "$v" "$f" || rc=$?
  [[ "$rc" -eq 0 && -f "$f" ]] || { echo "FATAL: mutation $v failed to materialize (rc=$rc)" >&2; exit 2; }
done

expect_red "remove id-token: write"                 "$SANDBOX/mutated-m1.yml"
expect_red "re-add NODE_AUTH_TOKEN env"             "$SANDBOX/mutated-m2.yml"
expect_red "no publish job (vacuous dispatch)"      "$SANDBOX/mutated-m3.yml"
expect_red "delete npm@^11 freshness step"          "$SANDBOX/mutated-m4.yml"
expect_red "jobs.publish parses to a non-map"       "$SANDBOX/mutated-m5.yml"
expect_pass "extra unrelated permission (superset)" "$SANDBOX/mutated-m6.yml"

# ---------------------------------------------------------------------------
# Verdict accounting. The floor compares a counter this file increments at each
# call site (CASES) against the verdict counters the helpers own — a neutered
# helper or a discarded verdict desyncs them, and a guard whose floor cannot
# watch its own machinery is vacuous (guard-vacuity-floor.test.sh shape).
# ---------------------------------------------------------------------------
_LATE_P="$PASS"; _LATE_F="$FAIL"
pass "late dispatch re-validation: pass() still increments (EXPECTED)" >/dev/null
fail "late dispatch re-validation: fail() still records (EXPECTED, not a real failure)" >/dev/null
if [[ "$PASS" -ne "$((_LATE_P + 1))" || "$FAIL" -ne "$((_LATE_F + 1))" ]]; then
  printf 'LATE DISPATCH RE-VALIDATION FAILED: PASS %s->%s (want +1), FAIL %s->%s (want +1). The assertion helpers were neutered or laundered.\n' \
    "$_LATE_P" "$PASS" "$_LATE_F" "$FAIL" >&2
  exit 2
fi
PASS=$((PASS - 1))
FAIL=$((FAIL - 1))
if [[ "$CASES" -ne "$((PASS + FAIL))" ]]; then
  echo "FATAL: verdict accounting desync: $CASES call sites but $((PASS + FAIL)) verdicts — assertions ran and their verdicts were discarded." >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -lt 11 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 11." >&2
  exit 1
fi
echo "$PASS passed, $FAIL failed ($((PASS + FAIL)) assertions)"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
