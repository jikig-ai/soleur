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
# CREDENTIAL-WIRING SURFACE (the member names the property, the checks name
# every channel that reaches it). `no-cred-wiring` does not stop at step env
# and `with:`: a token can reach npm's auth selection through `env:` at the
# job (`jobs.publish.env`) or workflow (top-level `env:`) level, through a
# `run:` body (env-prefixed `npm publish`, `export`, `.npmrc` heredoc,
# `npm config set`), and through a committed `packages/opencode-plugin/.npmrc`
# (read because the publish step's `working-directory:` is the project npmrc
# dir). All six are scanned. `no-environment` and `github-hosted-runner` pin
# the OIDC binding's other two silent-break channels: the npm-side trust
# entry is bound with NO environment (a job `environment:` changes the OIDC
# claims and re-E404s) and trusted publishing only works on GitHub-hosted
# runners. `npm11-step`/`npm-publish-retained` pin POSITION and SHAPE, not
# just presence: the install must precede the publish, and the publish must
# keep `--access public --ignore-scripts` (a bare `npm publish` publishes a
# scoped package as private or fails the access gate).
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
#   member: `id-token` | `no-cred-wiring` | `npm11-step` | `npm-publish-retained`
#         | `no-environment` | `github-hosted-runner` | `all`
#   exit 0 when the member (or every member, for `all`) holds; prints one
#   `VIOLATION: <member>` line per failure. `all` is the mutation-battery
#   predicate — a file failing ANY member is RED.
#
# run bodies are comment-stripped inside the probe: a `# npm install -g npm@^11`
# line inside a `run:` scalar cannot satisfy the CLI-floor member.
wiring_probe() {
  python3 - "$1" "$2" <<'PYG'
import os, re, sys, yaml

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

def want(m):
    return member in ("all", m)

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
    # Every channel by which a token can reach npm's auth selection:
    # env keys at workflow / job / step level, `with:` registry-url (setup-node
    # writes .npmrc _authToken), run-body writes (.npmrc / npm config set /
    # env-prefixed publish), and the project .npmrc at the publish step's
    # working-directory.
    key_pat = re.compile(r"AUTH_?TOKEN|_authToken|NPM_TOKEN|npm_config_", re.IGNORECASE)
    val_pat = re.compile(r"_authToken|secrets\.NPM_TOKEN", re.IGNORECASE)
    body_pat = re.compile(
        r"_authToken|NPM_TOKEN|AUTH_?TOKEN\s*=|npm\s+config\s+set", re.IGNORECASE)
    env_scopes = [
        ("workflow", doc.get("env")),
        ("jobs.publish", pub.get("env")),
    ]
    env_scopes += [
        ("step %d" % i, st.get("env"))
        for i, st in enumerate(steps) if isinstance(st, dict)
    ]
    for scope, env in env_scopes:
        if not isinstance(env, dict):
            continue
        for k, v in env.items():
            if key_pat.search(str(k)) or val_pat.search(str(v)):
                violations.append(
                    "no-cred-wiring: %s env carries credential wiring (%s)" % (scope, k))
    for i, st in enumerate(steps):
        if not isinstance(st, dict):
            continue
        with_ = st.get("with")
        if isinstance(with_, dict) and "registry-url" in with_:
            violations.append(
                "no-cred-wiring: step %d `with:` carries registry-url "
                "(writes .npmrc _authToken, masks OIDC auth)" % i)
    for i, st in enumerate(steps):
        m = body_pat.search(run_body(st))
        if m:
            violations.append(
                "no-cred-wiring: step %d run body carries credential wiring (%s)" % (i, m.group(0)))
    # The publish step's working-directory IS a project-npmrc dir; a committed
    # .npmrc carrying _authToken there masks OIDC selection identically.
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(path)))
    npmrc = os.path.join(repo_root, "packages", "opencode-plugin", ".npmrc")
    if os.path.isfile(npmrc):
        for line in open(npmrc):
            if re.search(r"_authToken|NPM_TOKEN", line):
                violations.append(
                    "no-cred-wiring: %s carries credential wiring" % npmrc)
                break

run_bodies = "\n".join(run_body(st) for st in steps)
if want("npm11-step"):
    install_idx = publish_idx = None
    for i, st in enumerate(steps):
        body = run_body(st)
        if install_idx is None and re.search(r"npm\s+install\s+-g\s+npm@\^11\b", body):
            install_idx = i
        if publish_idx is None and re.search(r"\bnpm\s+publish\b", body):
            publish_idx = i
    if install_idx is None:
        violations.append("npm11-step: no step installs npm@^11 (>= 11.5.1 floor)")
    elif publish_idx is not None and install_idx > publish_idx:
        violations.append(
            "npm11-step: npm@^11 install runs AFTER npm publish (bundled npm 10.x publishes)")
if want("npm-publish-retained"):
    if not re.search(r"\bnpm\s+publish\b", run_bodies):
        violations.append("npm-publish-retained: no step invokes `npm publish`")
    elif not re.search(r"\bnpm\s+publish\s+--access\s+public\s+--ignore-scripts\b", run_bodies):
        violations.append(
            "npm-publish-retained: `npm publish` lost its flag contract "
            "(--access public --ignore-scripts)")
if want("no-environment"):
    if pub.get("environment") is not None:
        violations.append(
            "no-environment: jobs.publish sets `environment:` — the npm-side "
            "trust entry is bound with no environment; OIDC claims would mismatch (E404)")
if want("github-hosted-runner"):
    runs_on = pub.get("runs-on")
    labels = runs_on if isinstance(runs_on, list) else [runs_on]
    if any("self-hosted" in str(l) for l in labels):
        violations.append(
            "github-hosted-runner: npm trusted publishing does not run on "
            "self-hosted runners (no OIDC exchange)")

if want("diagnose-on-failure") and os.environ.get("DIAG_MEMBER_NEUTER") != "1":
    # The failure-only diagnostic: the step after `npm publish` that replays the
    # OIDC exchange. Quantifies over the parsed steps list by index; the `if:` is
    # compared as a parsed `&&` conjunct SET (a substring check would accept
    # `failure() || always()`).
    pub_idx = None
    for i, st in enumerate(steps):
        if re.search(r"\bnpm\s+publish\b", run_body(st)):
            pub_idx = i
            break
    if pub_idx is None:
        violations.append("diagnose-on-failure: no step invokes `npm publish`")
    else:
        pst = steps[pub_idx]
        pid = pst.get("id")
        if not isinstance(pid, str) or not pid:
            violations.append("diagnose-on-failure: the publish step has no `id:`")
            pid = None
        coe = pst.get("continue-on-error")
        if coe is not None and str(coe).strip().lower() != "false":
            violations.append(
                "diagnose-on-failure: publish step sets continue-on-error "
                "(a failed publish would go green)")
        if "NPM_OIDC_VERDICT=not-exercised" not in run_body(pst):
            violations.append(
                "diagnose-on-failure: the already-published early exit does not print "
                "NPM_OIDC_VERDICT=not-exercised (a green run that never exercised OIDC reads as proof)")
        wanted = None
        if pid is not None:
            wanted = {"failure()", "steps.%s.outcome == 'failure'" % pid}
        found = False
        for st in steps[pub_idx + 1:]:
            if not isinstance(st, dict) or wanted is None:
                continue
            cond = str(st.get("if", "")).strip()
            m = re.fullmatch(r"\$\{\{(.*)\}\}", cond, re.S)
            if m:
                cond = m.group(1).strip()
            conj = {re.sub(r"\s+", " ", p.strip()) for p in cond.split("&&")}
            if conj == wanted and re.search(
                    r"(^|\s)bash\s+\.github/scripts/npm-oidc-diagnose\.sh(\s|$)", run_body(st)):
                found = True
                break
        if not found:
            violations.append(
                "diagnose-on-failure: no step after the publish step runs "
                "`bash .github/scripts/npm-oidc-diagnose.sh` under exactly "
                "`if: failure() && steps.<publish id>.outcome == 'failure'`")

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
for m in id-token no-cred-wiring npm11-step npm-publish-retained no-environment github-hosted-runner diagnose-on-failure; do
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
elif variant == "m7":  # job-level env carries a token (step-env channel bypass)
    pub.setdefault("env", {})["NODE_AUTH_TOKEN"] = "${{ secrets.NPM_TOKEN }}"
elif variant == "m8":  # workflow-level env carries a token
    doc.setdefault("env", {})["NPM_TOKEN"] = "x"
elif variant == "m9":  # job gains environment: (breaks the no-environment OIDC binding)
    pub["environment"] = "production"
elif variant == "m10":  # self-hosted runner (trusted publishing unsupported)
    pub["runs-on"] = "self-hosted"
elif variant == "m11":  # npm@^11 install moved AFTER npm publish
    install = publish = None
    for i, st in enumerate(pub.get("steps", [])):
        body = str(st.get("run", ""))
        if install is None and "npm install -g npm@^11" in body:
            install = i
        if publish is None and "npm publish" in body:
            publish = i
    if install is not None and publish is not None:
        pub["steps"].insert(publish + 1, pub["steps"].pop(install))
elif variant == "m12":  # npm publish loses its flag contract
    for st in pub.get("steps", []):
        if "npm publish --access public --ignore-scripts" in str(st.get("run", "")):
            st["run"] = str(st["run"]).replace(
                "npm publish --access public --ignore-scripts", "npm publish")
            break
elif variant == "m13":  # run-body credential write (npm config set _authToken)
    for st in pub.get("steps", []):
        if "npm publish" in str(st.get("run", "")):
            st["run"] = str(st["run"]) + \
                "\nnpm config set //registry.npmjs.org/:_authToken=dead\n"
            break
elif variant.startswith("d"):  # diagnose-on-failure mutations (Guard 1 matrix)
    steps = pub["steps"]
    didx = next((i for i, st in enumerate(steps)
                 if "npm-oidc-diagnose" in str(st.get("run", ""))), None)
    pidx = next((i for i, st in enumerate(steps)
                 if "npm publish" in str(st.get("run", ""))), None)
    ok_if = "failure() && steps.publish.outcome == 'failure'"
    if variant == "d1":  # delete the diagnose step
        if didx is not None:
            steps.pop(didx)
    elif variant == "d2":  # diagnose step moved BEFORE the publish step
        if didx is not None and pidx is not None:
            steps.insert(pidx, steps.pop(didx))
    elif variant == "d3":  # implicit success(): never runs on the failure it exists for
        steps[didx]["if"] = "steps.publish.outcome == 'failure'"
    elif variant == "d4a":  # always()
        steps[didx]["if"] = "always()"
    elif variant == "d4b":  # conjunct set no longer equal
        steps[didx]["if"] = "failure() || true"
    elif variant == "d5":  # publish failure no longer fails the job
        steps[pidx]["continue-on-error"] = True
    elif variant == "d6":  # wrong step id: the step never runs
        steps[didx]["if"] = "failure() && steps.nope.outcome == 'failure'"
    elif variant == "d7":  # step present, does nothing
        steps[didx]["run"] = "echo diagnose"
    elif variant == "d8":  # early exit loses the not-exercised marker
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "NPM_OIDC_VERDICT=not-exercised", "NPM_OIDC_X")
    elif variant == "d9a":  # must-pass superset: a second compliant step
        import copy
        steps.insert(didx + 1, copy.deepcopy(steps[didx]))
    elif variant == "d9b":  # must-pass: conjunct order reversed
        steps[didx]["if"] = "steps.publish.outcome == 'failure' && failure()"
    elif variant == "d9c":  # must-pass: wrapped in ${{ }}
        steps[didx]["if"] = "${{ " + ok_if + " }}"
    else:
        sys.stderr.write("unknown variant %s\n" % variant)
        raise SystemExit(2)
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

for v in m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13; do
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
expect_red "job-level env carries a token"          "$SANDBOX/mutated-m7.yml"
expect_red "workflow-level env carries a token"     "$SANDBOX/mutated-m8.yml"
expect_red "job gains environment: (binding break)" "$SANDBOX/mutated-m9.yml"
expect_red "self-hosted runner"                     "$SANDBOX/mutated-m10.yml"
expect_red "npm@^11 install after npm publish"      "$SANDBOX/mutated-m11.yml"
expect_red "npm publish loses flag contract"        "$SANDBOX/mutated-m12.yml"
expect_red "run-body npm config set _authToken"     "$SANDBOX/mutated-m13.yml"

# ---------------------------------------------------------------------------
# Guard 1 - diagnose-on-failure member. Rows run through a MEMBER-scoped probe so
# a red is attributed to this member (the whole-guard predicate would also go red
# on an unrelated member). d9a-c are must-PASS non-canonical inputs.
# ---------------------------------------------------------------------------
expect_red_member() { # expect_red_member <label> <file>
  CASES=$((CASES + 1))
  rc=0; wiring_probe "$2" diagnose-on-failure >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "diagnose-on-failure mutation caught: $1"
  else
    fail "diagnose-on-failure mutation SURVIVED: $1 left the member green"
  fi
}

expect_pass_member() { # expect_pass_member <label> <file>
  CASES=$((CASES + 1))
  rc=0; wiring_probe "$2" diagnose-on-failure >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "diagnose-on-failure compliant superset accepted: $1"
  else
    fail "diagnose-on-failure compliant superset REJECTED: $1"
  fi
}

for v in d1 d2 d3 d4a d4b d5 d6 d7 d8 d9a d9b d9c; do
  f="$SANDBOX/mutated-$v.yml"
  assert_fixture_dir "$(dirname "$f")"
  rc=0; mutate "$v" "$f" || rc=$?
  [[ "$rc" -eq 0 && -f "$f" ]] || { echo "FATAL: mutation $v failed to materialize (rc=$rc)" >&2; exit 2; }
done

expect_red_member "delete the diagnose step"                     "$SANDBOX/mutated-d1.yml"
expect_red_member "diagnose step moved before publish"           "$SANDBOX/mutated-d2.yml"
expect_red_member "if: loses failure() (implicit success())"     "$SANDBOX/mutated-d3.yml"
expect_red_member "if: always()"                                 "$SANDBOX/mutated-d4a.yml"
expect_red_member "if: failure() || true"                        "$SANDBOX/mutated-d4b.yml"
expect_red_member "publish step gains continue-on-error"         "$SANDBOX/mutated-d5.yml"
expect_red_member "if: references a wrong step id"               "$SANDBOX/mutated-d6.yml"
expect_red_member "script invocation replaced by echo"           "$SANDBOX/mutated-d7.yml"
expect_red_member "early exit loses the not-exercised marker"    "$SANDBOX/mutated-d8.yml"
expect_pass_member "second compliant diagnose step"              "$SANDBOX/mutated-d9a.yml"
expect_pass_member "conjunct order reversed"                     "$SANDBOX/mutated-d9b.yml"
expect_pass_member "if: wrapped in \${{ }}"                      "$SANDBOX/mutated-d9c.yml"

# Harness row (a): with the member neutered, a row that should be RED must read
# GREEN - proving the rows above can tell the member's presence from its absence.
CASES=$((CASES + 1))
rc=0; DIAG_MEMBER_NEUTER=1 wiring_probe "$SANDBOX/mutated-d1.yml" diagnose-on-failure >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "harness: a neutered diagnose-on-failure member lets mutation d1 survive (rows can fail)"
else
  fail "harness: neutering the diagnose-on-failure member did not change the d1 verdict (rows are vacuous)"
fi

# ---------------------------------------------------------------------------
# Guard 2 - classifier and log-safety of .github/scripts/npm-oidc-diagnose.sh.
# A stub `curl` (selected through PATH, base environment `env -i`) answers the two
# requests the script makes and RECORDS its argv; it refuses (exit 64) any argv it
# does not model. No case can reach the network.
# ---------------------------------------------------------------------------
command -v jq >/dev/null || { echo "FATAL: jq required"; exit 2; }
DIAG_SCRIPT="${DIAG_SCRIPT:-$REPO_ROOT/.github/scripts/npm-oidc-diagnose.sh}"
STUBBIN="$SANDBOX/stubbin"; mkdir -p "$STUBBIN"; assert_fixture_dir "$STUBBIN"
cat > "$STUBBIN/curl" <<'STUBEOF'
#!/usr/bin/env bash
set -u
D="${STUB_DIR:?}"
n=$(( $(grep -c '^CALL ' "$D/calls.log" 2>/dev/null || true) + 1 ))
{ echo "CALL $n"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$D/calls.log"
refuse() { echo "REFUSED $*" >> "$D/refused"; exit 64; }
args=("$@"); out=""; fmt=""; url=""; cfg=0; i=0
while [ "$i" -lt "$#" ]; do
  a="${args[$i]}"
  case "$a" in
    --disable|-s|-S|-sS|-G) ;;
    --noproxy|--connect-timeout|--max-time|-X|--data-urlencode) i=$((i + 1)) ;;
    -o) i=$((i + 1)); out="${args[$i]}" ;;
    -w) i=$((i + 1)); fmt="${args[$i]}" ;;
    -K) i=$((i + 1)); [ "${args[$i]}" = "-" ] || refuse "-K ${args[$i]}"; cfg=1 ;;
    -*) refuse "$a" ;;
    *) url="$a" ;;
  esac
  i=$((i + 1))
done
[ -n "$url" ] || refuse "no url"
if [ "$cfg" -eq 1 ]; then
  printf 'BEARER %s %s\n' "$n" "$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p')" >> "$D/bearer.log"
fi
case "$url" in
  */oidc/token/exchange/*)
    cp "${STUB_STDOUT:-/dev/null}" "$D/stdout-at-exchange" 2>/dev/null
    code="${STUB_EXCH_CODE:-401}"; body="${STUB_EXCH_BODY:-}"; rc="${STUB_EXCH_RC:-0}" ;;
  *)
    code="${STUB_TOK_CODE:-200}"; body="${STUB_TOK_BODY:-}"; rc="${STUB_TOK_RC:-0}" ;;
esac
[ -z "$out" ] || printf '%s' "$body" > "$out"
case "$fmt" in *http_code*) printf '%s' "$code" ;; esac
exit "$rc"
STUBEOF
chmod +x "$STUBBIN/curl"

rnd() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }
not() { ! "$@"; }

# Battery mode: `real` routes each assertion through pass/fail (CASES-counted);
# `quiet` only counts failures, so a mutant run can be scored without touching
# the suite's own verdict counters.
B_MODE=real; B_BAD=0; B_SEQ=0; DIAG_BASH=(bash)
bchk() { # bchk <label> <rc>
  if [[ "$B_MODE" == "real" ]]; then
    CASES=$((CASES + 1))
    if [[ "$2" -eq 0 ]]; then pass "diagnose: $1"; else fail "diagnose: $1"; fi
  elif [[ "$2" -ne 0 ]]; then
    B_BAD=$((B_BAD + 1))
  fi
}
# In quiet mode the first failing assertion decides the mutant, so the rest of the
# battery is skipped (it would only re-prove the same kill).
quiet_done() { [[ "$B_MODE" == "quiet" && "$B_BAD" -gt 0 ]]; }
ck() { local label="$1"; shift; quiet_done && return 0; "$@" >/dev/null 2>&1; bchk "$label" "$?"; }

# run_diag <name> [VAR=val | UNSET=NAME ...]  - runs $DIAG_SCRIPT_UNDER once.
run_diag() {
  local name="$1"; shift
  quiet_done && return 0
  B_SEQ=$((B_SEQ + 1))
  CD="$SANDBOX/diag-$B_SEQ-$name"
  assert_fixture_dir "$CD"
  mkdir -p "$CD/tmp" "$CD/home"
  ID_TOK="eyJ$(rnd).$(rnd).$(rnd)"; REQ_TOK="$(rnd)"; SECRET="$(rnd)"
  local envs=(
    "PATH=$STUBBIN:/usr/local/bin:/usr/bin:/bin" "HOME=$CD/home" "TMPDIR=$CD/tmp"
    "STUB_DIR=$CD" "STUB_STDOUT=$CD/out"
    "ACTIONS_ID_TOKEN_REQUEST_URL=http://127.0.0.1:9/token?api=1"
    "ACTIONS_ID_TOKEN_REQUEST_TOKEN=$REQ_TOK"
    "STUB_TOK_CODE=200" "STUB_TOK_BODY={\"value\":\"$ID_TOK\"}"
    "STUB_EXCH_CODE=401"
    "STUB_EXCH_BODY={\"message\":\"OIDC token exchange error - unauthorized\",\"detail\":\"$SECRET\"}"
  )
  local a e kept
  for a in "$@"; do
    case "$a" in
      UNSET=*)
        kept=()
        for e in "${envs[@]}"; do
          [[ "$e" == "${a#UNSET=}="* ]] || kept+=("$e")
        done
        envs=("${kept[@]}") ;;
      *) envs+=("$a") ;;
    esac
  done
  DRC=0
  env -i "${envs[@]}" "${DIAG_BASH[@]}" "$DIAG_SCRIPT_UNDER" >"$CD/out" 2>"$CD/err" || DRC=$?
  cat "$CD/out" "$CD/err" > "$CD/all"
  grep -v '^::add-mask::' "$CD/all" > "$CD/vis" || true
}

verdict_is() { grep -qx "NPM_OIDC_VERDICT=$1" "$CD/out"; }
one_verdict() { [[ "$(grep -c '^NPM_OIDC_VERDICT=' "$CD/out")" -eq 1 ]]; }
only_allowed_annotations() {
  ! grep -E '^::' "$CD/all" | grep -vE '^::(add-mask::[A-Za-z0-9._~+/=-]+|error title=npm trusted publisher::.+)$' | grep -q .
}
call_block() { awk -v n="$1" '$0 == "CALL " n {f=1; next} /^CALL /{f=0} f' "$CD/calls.log"; }
calls_total() { grep -c '^CALL ' "$CD/calls.log" 2>/dev/null || true; }

diag_battery() { # diag_battery <script-under-test>
  DIAG_SCRIPT_UNDER="$1"; B_SEQ=$((B_SEQ + 100))

  # --- measured 401 (the registry's real answer to an unauthorised bearer) ---
  run_diag c401
  ck "401: exit 0"                                   test "$DRC" -eq 0
  ck "401: trusted-publisher verdict"                verdict_is trusted-publisher-missing-or-mismatched
  ck "401: exactly one verdict line"                 one_verdict
  ck "401: status line"                              grep -qx 'status=401' "$CD/out"
  ck "401: registry message surfaced"                grep -qx 'message=OIDC token exchange error - unauthorized' "$CD/out"
  ck "401: expected repository value"                grep -qx 'repository=jikig-ai/soleur' "$CD/out"
  ck "401: expected workflow value"                  grep -qx 'workflow=npm-publish.yml' "$CD/out"
  ck "401: expected environment value"               grep -qx 'environment=(none)' "$CD/out"
  ck "401: one-line remediation"                     grep -qF 'npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish' "$CD/out"
  ck "401: runbook pointer"                          grep -qF 'knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md' "$CD/out"
  ck "401: id-token never printed (add-mask line aside)"  not grep -qF -- "$ID_TOK" "$CD/vis"
  ck "401: request token never printed"              not grep -qF -- "$REQ_TOK" "$CD/all"
  ck "401: second registry-body field never printed" not grep -qF -- "$SECRET" "$CD/all"
  ck "401: exactly one add-mask line"                test "$(grep -c '^::add-mask::' "$CD/out")" -eq 1
  ck "401: the add-mask line masks the id-token"     grep -qxF "::add-mask::$ID_TOK" "$CD/out"
  ck "401: mask printed BEFORE the exchange call"    grep -qxF "::add-mask::$ID_TOK" "$CD/stdout-at-exchange"
  ck "401: only allow-listed :: annotations"         only_allowed_annotations
  ck "401: stub exercised exactly twice (floor)"     test "$(calls_total)" -eq 2
  ck "401: stub refused nothing"                     test ! -e "$CD/refused"
  ck "401: token fetch uses -G"                      bash -c "$(declare -f call_block); CD='$CD'; call_block 1 | grep -qx 'ARG -G'"
  ck "401: token fetch carries the audience arg"     bash -c "$(declare -f call_block); CD='$CD'; call_block 1 | grep -qx 'ARG audience=npm:registry.npmjs.org'"
  ck "401: token fetch keeps the URL verbatim"       bash -c "$(declare -f call_block); CD='$CD'; call_block 1 | grep -qx 'ARG http://127.0.0.1:9/token?api=1'"
  ck "401: exchange is a POST"                       bash -c "$(declare -f call_block); CD='$CD'; call_block 2 | grep -A1 -x 'ARG -X' | grep -qx 'ARG POST'"
  ck "401: exchange URL exact"                       bash -c "$(declare -f call_block); CD='$CD'; call_block 2 | grep -qx 'ARG https://registry.npmjs.org/-/npm/v1/oidc/token/exchange/package/@soleur%2fopencode'"
  ck "401: bearer flowed (request token to the fetch)"  grep -qx "BEARER 1 $REQ_TOK" "$CD/bearer.log"
  ck "401: bearer flowed (id-token to the exchange)"    grep -qx "BEARER 2 $ID_TOK" "$CD/bearer.log"
  ck "401: no bearer value in any argv"              not grep -qF -e "$REQ_TOK" -e "$ID_TOK" "$CD/calls.log"
  ck "401: every call has a connect timeout"         test "$(grep -c -x 'ARG --connect-timeout' "$CD/calls.log")" -eq 2
  ck "401: every call has a max time"                test "$(grep -c -x 'ARG --max-time' "$CD/calls.log")" -eq 2
  ck "401: temp dir removed"                         test -z "$(ls -A "$CD/tmp")"

  # --- other authorisation-shaped statuses ---
  local c
  for c in 403 404; do
    run_diag "c$c" "STUB_EXCH_CODE=$c"
    ck "$c: trusted-publisher verdict"               verdict_is trusted-publisher-missing-or-mismatched
    ck "$c: exit 0"                                  test "$DRC" -eq 0
  done

  # --- success shapes: the exchange works, so the failure is elsewhere ---
  for c in 200 204; do
    run_diag "c$c" "STUB_EXCH_CODE=$c" "STUB_EXCH_BODY={\"token\":\"npm_$(rnd)\"}"
    ck "$c: exchange-ok verdict"                     verdict_is exchange-ok
    ck "$c: exchange body never printed"             not grep -qF -- "npm_" "$CD/vis"
    ck "$c: exit 0"                                  test "$DRC" -eq 0
  done
  run_diag c200secret "STUB_EXCH_CODE=200"
  ck "200: second registry-body field never printed" not grep -qF -- "$SECRET" "$CD/all"

  # --- transient / unclassified statuses are NOT a trust verdict ---
  for c in 400 422 429 503 301; do
    run_diag "c$c" "STUB_EXCH_CODE=$c"
    ck "$c: registry-error verdict"                  verdict_is registry-error
    ck "$c: status reported"                         grep -qx "status=$c" "$CD/out"
    ck "$c: exit 0"                                  test "$DRC" -eq 0
  done
  run_diag crc28 "STUB_EXCH_CODE=000" "STUB_EXCH_RC=28"
  ck "curl rc 28: registry-error verdict"            verdict_is registry-error
  ck "curl rc 28: exit 0"                            test "$DRC" -eq 0

  # --- the id-token could not be obtained ---
  run_diag cnourl "UNSET=ACTIONS_ID_TOKEN_REQUEST_URL"
  ck "no request URL: id-token-missing"              verdict_is id-token-missing
  ck "no request URL: curl never invoked"            test ! -e "$CD/calls.log"
  ck "no request URL: no add-mask line"              not grep -q '^::add-mask::' "$CD/out"
  ck "no request URL: exit 0"                        test "$DRC" -eq 0
  run_diag cnotok "UNSET=ACTIONS_ID_TOKEN_REQUEST_TOKEN"
  ck "no request token: id-token-missing"            verdict_is id-token-missing
  run_diag cfetch500 "STUB_TOK_CODE=500"
  ck "token fetch 500: id-token-fetch-failed"        verdict_is id-token-fetch-failed
  ck "token fetch 500: exchange never attempted"     test "$(calls_total)" -eq 1
  ck "token fetch 500: exit 0"                       test "$DRC" -eq 0
  run_diag cfetchempty "STUB_TOK_BODY={}"
  ck "empty token body: id-token-fetch-failed"       verdict_is id-token-fetch-failed
  run_diag cfetchbad 'STUB_TOK_BODY={"value":"a\"b"}'
  ck "token with a quote: id-token-fetch-failed"     verdict_is id-token-fetch-failed
  ck "token with a quote: no add-mask, no exchange"  test "$(grep -c '^::add-mask::' "$CD/out")$(calls_total)" = "01"

  # --- registry-controlled text must never become a workflow command ---
  local p
  for p in 'x\n::notice::PASS' 'x\r\n::error::boom' 'x%0A::notice::PASS' 'x ::notice::PASS' '::stop-commands::tok' 'x\nNPM_OIDC_VERDICT=exchange-ok'; do
    run_diag cinject "STUB_EXCH_BODY={\"message\":\"$p\"}"
    ck "inject '$p': only allow-listed :: lines"     only_allowed_annotations
    ck "inject '$p': one verdict line"               one_verdict
    ck "inject '$p': still the trust verdict"        verdict_is trusted-publisher-missing-or-mismatched
  done
  ck "U+2028 stripped from the printed message"      not env LC_ALL=C grep -q $'\xe2\x80\xa8' "$CD/out"

  # --- xtrace must not leak a bearer ---
  DIAG_BASH=(bash -x)
  run_diag cxtrace
  DIAG_BASH=(bash)
  ck "xtrace: exit 0"                                test "$DRC" -eq 0
  ck "xtrace: id-token not traced"                   not grep -qF -- "$ID_TOK" "$CD/vis"
  ck "xtrace: request token not traced"              not grep -qF -- "$REQ_TOK" "$CD/all"

  # --- env overrides are reflected in the recorded requests (must-pass input) ---
  run_diag coverride "OIDC_DIAG_REGISTRY=https://registry.invalid" "OIDC_DIAG_PACKAGE=@x/y"
  ck "override: verdict still classified"            verdict_is trusted-publisher-missing-or-mismatched
  ck "override: exchange URL reflects registry+package"  bash -c "$(declare -f call_block); CD='$CD'; call_block 2 | grep -qx 'ARG https://registry.invalid/-/npm/v1/oidc/token/exchange/package/@x%2fy'"
  ck "override: audience follows the registry host"  bash -c "$(declare -f call_block); CD='$CD'; call_block 1 | grep -qx 'ARG audience=npm:registry.invalid'"
}

# Instrument self-test: the quiet-mode helper must count a failure and ignore a pass.
B_MODE=quiet; B_BAD=0
bchk "self-test failing check" 1; bchk "self-test passing check" 0
_selftest_bad="$B_BAD"; B_MODE=real; B_BAD=0
CASES=$((CASES + 1))
if [[ "$_selftest_bad" -eq 1 ]]; then pass "harness: quiet bchk counts exactly the failing check"; else fail "harness: quiet bchk miscounted ($_selftest_bad, want 1)"; fi

# The real script, scored through the suite's own pass/fail helpers.
B_MODE=real
diag_battery "$DIAG_SCRIPT"

# Mutants: each is a sandbox copy of the script with ONE edit (the real script is
# never touched). A mutant is scored by running the SAME battery in quiet mode and
# requiring >= 1 failing assertion; a pristine copy must score 0 (control).
B_MODE=quiet
PRISTINE="$SANDBOX/diag-pristine.sh"
cp "$DIAG_SCRIPT" "$PRISTINE" 2>/dev/null || : > "$PRISTINE"
chmod +x "$PRISTINE"
B_BAD=0; diag_battery "$PRISTINE"; _ctl_bad="$B_BAD"
B_MODE=real
CASES=$((CASES + 1))
if [[ "$_ctl_bad" -eq 0 ]]; then pass "diagnose: pristine copy scores 0 failing assertions (mutant control)"; else fail "diagnose: pristine copy scored $_ctl_bad failing assertions (mutant control is red)"; fi

diag_mutant() { # diag_mutant <label> <sed-script>
  local m="$SANDBOX/diag-mutant-$1.sh"
  assert_fixture_dir "$(dirname "$m")"
  sed "$2" "$PRISTINE" > "$m"; chmod +x "$m"
  if cmp -s "$m" "$PRISTINE"; then
    CASES=$((CASES + 1))
    fail "diagnose mutant '$1': the edit did NOT land (a mutation that does not land reports the baseline)"
    return
  fi
  B_MODE=quiet; B_BAD=0; diag_battery "$m"; local bad="$B_BAD"; B_MODE=real
  CASES=$((CASES + 1))
  if [[ "$bad" -gt 0 ]]; then
    pass "diagnose mutant caught: $1 ($bad failing assertions)"
  else
    fail "diagnose mutant SURVIVED: $1 left every assertion green"
  fi
}

# shellcheck disable=SC2016  # the sed programs are literal text, not shell expansions
diag_mutant leak-id-token      's|^printf .::add-mask::.*|&; echo "leak=$idtok"|'
diag_mutant drop-add-mask      '/^printf .::add-mask::/d'
diag_mutant 401-as-exchange-ok 's/^  2??) /  2??|401|404) /'
diag_mutant 429-as-trust       's/^  401|403|404) /  4??|5??) /'
diag_mutant exit-1-on-verdict  '$ s/^exit 0$/exit 1/'
diag_mutant dispatch-no-curl   's/| curl /| true /'
# shellcheck disable=SC2016
diag_mutant no-sanitiser       's/^clean() {.*/clean() { printf "%s" "$1"; }/'
# shellcheck disable=SC2016
diag_mutant no-key-prefix      's/^say() {.*/say() { printf "%s\\n" "$2"; }/'
diag_mutant token-fetch-no-G   's/ -G / /'
diag_mutant no-audience-arg    's/--data-urlencode "audience=[^"]*"//'
diag_mutant keep-xtrace        '/^set +x$/d'

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
if [[ "$((PASS + FAIL))" -lt 139 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 139." >&2
  exit 1
fi
echo "$PASS passed, $FAIL failed ($((PASS + FAIL)) assertions)"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
# Last line, printed only on a clean run: the discoverability literal. A bare
# `0 failed` substring-matches `10 failed`, so the plan keys on this token.
echo "NPM_PUBLISH_OIDC_SUITE=PASS"
