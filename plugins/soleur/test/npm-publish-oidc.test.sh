#!/usr/bin/env bash
# shellcheck disable=SC2016  # the mutant sed programs are literal text, not shell expansions
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
# SECOND SUBJECT (Guard 1 member 7 + Guard 2, added with the failure-only diagnostic):
# `diagnose-on-failure` pins that a failed `npm publish` always reaches the diagnose step
# (exactly one publish step of any spelling, whose control flow - echo lines aside - equals a
# pinned skeleton: guarded `if ! npm publish ...; then exit 1`, marker before the early
# `exit 0`, nothing that swallows or skips; and a diagnose step that is exactly
# `bash .github/scripts/npm-oidc-diagnose.sh` under `if: failure() && steps.<id>.outcome ==
# 'failure'` with no working-directory/shell/env/defaults at any level). Guard 2
# drives `.github/scripts/npm-oidc-diagnose.sh` against a stub `curl` (PATH-selected, `env -i`
# base, no network): classification table, log safety (bearers off argv and out of every
# output stream, injection payloads, truncation), derived values, and 31
# sandbox-copy mutants of the script that must each fail the same battery (a pristine copy must
# score 0). It lives in this file, not .github/scripts/test/, because it shares the
# workflow-wiring guard's fixtures. Prints NPM_PUBLISH_OIDC_SUITE=PASS last, only on a clean run.
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

KNOWN_MEMBERS = ("all", "id-token", "no-cred-wiring", "npm11-step",
                 "npm-publish-retained", "no-environment", "github-hosted-runner",
                 "diagnose-on-failure")
if member not in KNOWN_MEMBERS:
    # A typo'd member name must never read as a passing member.
    sys.stderr.write("VIOLATION: unknown member %r\n" % member)
    raise SystemExit(2)

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
    # Any spelling of a publish counts: `npm publish`, `pnpm publish`, `npm --x publish`, `npx ... publish`.
    pub_re = re.compile(r"\b(?:npm|pnpm|yarn|bun|npx)\b[^\n;|&]*\bpublish\b")
    def joined(st):
        return re.sub(r"\\\n\s*", " ", run_body(st))
    pub_steps = [i for i, st in enumerate(steps)
                 if pub_re.search(joined(st)) or re.search(r"publish", str(st.get("uses", "")), re.I)]
    if len(pub_steps) != 1:
        violations.append(
            "diagnose-on-failure: exactly one step must publish (found %d); a decoy or second "
            "publish step is not covered by the diagnose wiring" % len(pub_steps))
    pub_idx = pub_steps[0] if pub_steps else None
    if pub_idx is not None:
        pst = steps[pub_idx]
        pid = pst.get("id")
        if not isinstance(pid, str) or not pid:
            violations.append("diagnose-on-failure: the publish step has no `id:`")
            pid = None
        for scope, node in (("step", pst), ("job", pub)):
            coe = node.get("continue-on-error")
            if coe is not None and str(coe).strip().lower() != "false":
                violations.append(
                    "diagnose-on-failure: %s sets continue-on-error "
                    "(a failed publish would go green)" % scope)
        for k in ("if", "shell"):
            if pst.get(k) is not None:
                violations.append("diagnose-on-failure: the publish step sets `%s:`" % k)
        # Interpreter-affecting environment (BASH_ENV, NODE_OPTIONS, PATH, LD_*) can make a publish a
        # no-op that exits 0 without touching the run body, so the env of the publish step is pinned
        # to the two names its body reads, and job/workflow env must be empty.
        if set((pst.get("env") or {}).keys()) != {"EVENT_NAME", "REF_NAME"}:
            violations.append("diagnose-on-failure: the publish step env must be exactly {EVENT_NAME, REF_NAME}")
        if pst.get("working-directory") != "packages/opencode-plugin":
            violations.append("diagnose-on-failure: the publish step working-directory must be packages/opencode-plugin")
        for scope, node in (("job", pub), ("workflow", doc)):
            if node.get("env"):
                violations.append("diagnose-on-failure: %s-level env must be empty" % scope)
        for j, other in enumerate(steps):
            if j != pub_idx and isinstance(other, dict) and other.get("continue-on-error") not in (None, False) \
                    and str(other.get("continue-on-error")).strip().lower() != "false":
                violations.append("diagnose-on-failure: step %d sets continue-on-error" % j)
        # CONTROL-FLOW SKELETON. Pattern greps over the publish body are satisfied by dead
        # branches, `trap ... EXIT`, an unconditional early exit and similar, so the body is
        # reduced to its control flow and compared to the golden skeleton: plain `echo "..."`
        # lines are dropped (they cannot change flow; the marker echo becomes <MARKER>), every
        # other line must match exactly. An intentional change to this step's flow therefore
        # reds here and must update the golden below in the same diff.
        golden = r"""set -euo pipefail
if [[ "$EVENT_NAME" == "release" ]]; then
RAW_TAG="$REF_NAME"
else
RAW_TAG=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | sed -n '1p')
fi
VERSION="${RAW_TAG#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
exit 1
fi
if npm view "@soleur/opencode@$VERSION" version >/dev/null 2>&1; then
<MARKER>
exit 0
fi
npm version --no-git-tag-version -- "$VERSION"
if ! npm publish --access public --ignore-scripts; then
exit 1
fi"""
        skel = []
        for l in run_body(pst).split("\n"):
            t = l.strip()
            if not t:
                continue
            if t == 'echo "NPM_OIDC_VERDICT=not-exercised"':
                skel.append("<MARKER>")
                continue
            em = re.fullmatch(r"""echo (?:"([^"]*)"|'([^']*)')(?: >&2)?""", t)
            # An echo is inert only when its body has no command/parameter substitution or escape:
            # `echo "$(printf x >> .npmrc)"` is an echo line that changes what npm publishes.
            if em and not re.search(r"\$\(|\$\{|`|\\", em.group(1) or em.group(2) or ""):
                continue
            skel.append(re.sub(r"\s+", " ", t))
        got = "\n".join(skel)
        if got != golden:
            want_l, got_l = golden.split("\n"), got.split("\n")
            first = next((i for i in range(max(len(want_l), len(got_l)))
                          if (want_l[i] if i < len(want_l) else None) != (got_l[i] if i < len(got_l) else None)), 0)
            violations.append(
                "diagnose-on-failure: the publish step's control flow differs from the pinned skeleton "
                "at line %d (want %r, got %r)" % (
                    first + 1, want_l[first] if first < len(want_l) else None,
                    got_l[first] if first < len(got_l) else None))
        wanted = None
        if pid is not None:
            wanted = {"failure()", "steps.%s.outcome == 'failure'" % pid}
        # Anything that could re-point the script (a cwd, a shell, an env, a default) is refused at
        # every level, not only on the step.
        hoisted = any(isinstance(n.get("defaults"), dict) and n["defaults"].get("run") for n in (doc, pub))
        found = False
        for st in steps[pub_idx + 1:]:
            if not isinstance(st, dict) or wanted is None:
                continue
            cond = str(st.get("if", "")).strip()
            m = re.fullmatch(r"\$\{\{(.*)\}\}", cond, re.S)
            if m:
                cond = m.group(1).strip()
            conj = {re.sub(r"\s+", " ", p.strip()) for p in cond.split("&&")}
            clean_step = (
                re.fullmatch(r"bash \.github/scripts/npm-oidc-diagnose\.sh", run_body(st).strip())
                and not st.get("working-directory") and not st.get("env") and not st.get("shell")
                and not st.get("continue-on-error") and not hoisted)
            if conj == wanted and clean_step:
                found = True
                break
        if not found:
            violations.append(
                "diagnose-on-failure: no step after the publish step is exactly "
                "`bash .github/scripts/npm-oidc-diagnose.sh` (no working-directory, shell, env, "
                "continue-on-error or defaults.run at step, job or workflow level) under exactly "
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
    elif variant == "d10":  # failed publish no longer fails the step (the last `exit 1` -> `exit 0`)
        r = str(steps[pidx]["run"]); i = r.rfind("exit 1")
        steps[pidx]["run"] = r[:i] + "exit 0" + r[i + 6:]
    elif variant == "d11":  # `|| true` swallows the publish failure
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "npm publish --access public --ignore-scripts; then",
            "npm publish --access public --ignore-scripts || true; then")
    elif variant == "d12":  # errexit off
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace("set -euo pipefail", "set +e", 1)
    elif variant == "d13":  # job-level continue-on-error
        pub["continue-on-error"] = True
    elif variant == "d14":  # decoy step ahead of the real publish, carrying the id
        decoy = {"name": "decoy", "id": "publish", "run": "echo npm publish NPM_OIDC_VERDICT=not-exercised"}
        steps[pidx]["id"] = "realpublish"
        steps.insert(pidx, decoy)
    elif variant == "d15":  # script invocation short-circuited
        steps[didx]["run"] = "true || bash .github/scripts/npm-oidc-diagnose.sh"
    elif variant == "d16":  # script path broken by a working-directory
        steps[didx]["working-directory"] = "packages/opencode-plugin"
    elif variant == "d17":  # early exit no longer exits
        r = str(steps[pidx]["run"]); i = r.find("exit 0")
        steps[pidx]["run"] = r[:i] + "true" + r[i + 6:]
    elif variant == "d18":  # destination override injected into the diagnose step
        steps[didx]["env"] = {"OIDC_DIAG_REGISTRY": "https://evil.example"}
    elif variant == "d19":  # publish becomes a dry run
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "npm publish --access public --ignore-scripts; then",
            "npm publish --access public --ignore-scripts --dry-run; then")
    elif variant == "d20":  # diagnose step tolerated-failure
        steps[didx]["continue-on-error"] = True
    elif variant == "d21":  # job-level default cwd re-points the script
        pub["defaults"] = {"run": {"working-directory": "packages/opencode-plugin"}}
    elif variant == "d22":  # workflow-level default shell
        doc["defaults"] = {"run": {"shell": "python3 {0}"}}
    elif variant == "d23":  # EXIT trap overrides the status
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "set -euo pipefail", "set -euo pipefail\ntrap 'exit 0' EXIT", 1)
    elif variant == "d24":  # unconditional early exit: publish is unreachable
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "npm version --no-git-tag-version",
            "echo NPM_OIDC_VERDICT=not-exercised\n          exit 0\n          npm version --no-git-tag-version", 1)
    elif variant == "d25":  # marker printed into the void
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            'echo "NPM_OIDC_VERDICT=not-exercised"', 'echo "NPM_OIDC_VERDICT=not-exercised" >/dev/null')
    elif variant == "d26":  # publish step never runs
        steps[pidx]["if"] = "${{ false }}"
    elif variant == "d27":  # a second publish spelled differently
        steps.insert(pidx + 1, {"name": "x", "run": "pnpm publish --access public"})
    elif variant == "d28":  # a second, guarded copy of the publish step with its own id
        import copy
        dup = copy.deepcopy(steps[pidx]); dup["id"] = "publish2"
        steps.insert(pidx + 1, dup)
    elif variant == "d29":  # failed-publish branch exits only in a comment
        r = str(steps[pidx]["run"]); i = r.rfind("exit 1")
        steps[pidx]["run"] = r[:i] + "echo failed # exit 1" + r[i + 6:]
    elif variant == "d30":  # publish-step env that can neuter npm
        steps[pidx].setdefault("env", {})["BASH_ENV"] = "/dev/null"
    elif variant == "d31":  # job-level env
        pub["env"] = {"NODE_OPTIONS": "--require /dev/null"}
    elif variant == "d32":  # workflow-level env
        doc["env"] = {"PATH": "/nonexistent"}
    elif variant == "d33":  # an echo line that rewrites .npmrc through a substitution
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "npm version --no-git-tag-version",
            "echo \"$(printf 'dry-run=true\\n' >> .npmrc)\"\n          npm version --no-git-tag-version", 1)
    elif variant == "d34":  # second publish hidden behind a line continuation, failure tolerated
        steps.insert(pidx + 1, {"name": "x", "continue-on-error": True, "run": "npm \\\n  publish --access public || true"})
    elif variant == "d35":  # a publish action whose failure is tolerated
        steps.insert(pidx + 1, {"name": "x", "uses": "owner/npm-publish@v3", "continue-on-error": True})
    elif variant == "d36":  # publish runs from a directory with its own .npmrc
        steps[pidx]["working-directory"] = "packages/opencode-plugin/../.."
    elif variant == "d9d":  # must-pass: extra echo lines and a comment change no flow
        steps[pidx]["run"] = str(steps[pidx]["run"]).replace(
            "npm version --no-git-tag-version",
            "# a comment\n          echo \"about to publish\"\n          npm version --no-git-tag-version", 1)
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

for v in d1 d2 d3 d4a d4b d5 d6 d7 d8 d9a d9b d9c d9d d10 d11 d12 d13 d14 d15 d16 d17 d18 d19 d20 d21 d22 d23 d24 d25 d26 d27 d28 d29 d30 d31 d32 d33 d34 d35 d36; do
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
expect_red_member "failed-publish branch exits 0"                "$SANDBOX/mutated-d10.yml"
expect_red_member "publish swallowed with || true"               "$SANDBOX/mutated-d11.yml"
expect_red_member "errexit switched off (set +e)"                "$SANDBOX/mutated-d12.yml"
expect_red_member "job-level continue-on-error"                  "$SANDBOX/mutated-d13.yml"
expect_red_member "decoy step carrying the publish id"           "$SANDBOX/mutated-d14.yml"
expect_red_member "diagnose run short-circuited (true || ...)"   "$SANDBOX/mutated-d15.yml"
expect_red_member "diagnose step gains a working-directory"      "$SANDBOX/mutated-d16.yml"
expect_red_member "early exit stops exiting"                     "$SANDBOX/mutated-d17.yml"
expect_red_member "diagnose step gains a destination env"        "$SANDBOX/mutated-d18.yml"
expect_red_member "publish becomes a dry run"                    "$SANDBOX/mutated-d19.yml"
expect_red_member "diagnose step continue-on-error"              "$SANDBOX/mutated-d20.yml"
expect_red_member "job-level defaults.run.working-directory"     "$SANDBOX/mutated-d21.yml"
expect_red_member "workflow-level defaults.run.shell"            "$SANDBOX/mutated-d22.yml"
expect_red_member "EXIT trap overrides the status"               "$SANDBOX/mutated-d23.yml"
expect_red_member "unconditional early exit before publish"      "$SANDBOX/mutated-d24.yml"
expect_red_member "marker printed to /dev/null"                  "$SANDBOX/mutated-d25.yml"
expect_red_member "publish step if: false"                       "$SANDBOX/mutated-d26.yml"
expect_red_member "second publish spelled pnpm publish"          "$SANDBOX/mutated-d27.yml"
expect_red_member "second guarded publish step, own id"          "$SANDBOX/mutated-d28.yml"
expect_red_member "failed-publish exit only in a comment"        "$SANDBOX/mutated-d29.yml"
expect_pass_member "extra echo and comment lines"                "$SANDBOX/mutated-d9d.yml"
expect_red_member "publish-step env BASH_ENV"                    "$SANDBOX/mutated-d30.yml"
expect_red_member "job-level env NODE_OPTIONS"                   "$SANDBOX/mutated-d31.yml"
expect_red_member "workflow-level env PATH"                      "$SANDBOX/mutated-d32.yml"
expect_red_member "echo carrying a command substitution"         "$SANDBOX/mutated-d33.yml"
expect_red_member "second publish behind a line continuation"    "$SANDBOX/mutated-d34.yml"
expect_red_member "tolerated publish action (uses:)"             "$SANDBOX/mutated-d35.yml"
expect_red_member "publish working-directory re-pointed"         "$SANDBOX/mutated-d36.yml"

# An unknown member name must be a hard error, never a passing member.
CASES=$((CASES + 1))
rc=0; wiring_probe "$WF" no-such-member >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "wiring_probe exits 2 on an unknown member name"; else fail "wiring_probe accepted an unknown member (rc=$rc)"; fi

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
    --noproxy|--proto|--connect-timeout|--max-time|-X|--data-urlencode) i=$((i + 1)) ;;
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
# A PATH that has everything the script needs EXCEPT jq (a missing binary is modelled by its
# absence, never by emptying PATH, which would remove the rest too).
NOJQ="$SANDBOX/nojq"; mkdir -p "$NOJQ"; assert_fixture_dir "$NOJQ"
for _t in bash tr sed cut mktemp rm rmdir wc cat; do
  _src="$(command -v "$_t")"; [[ "$_src" == /* ]] && ln -sf "$_src" "$NOJQ/$_t"
done
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
    "ACTIONS_ID_TOKEN_REQUEST_URL=https://127.0.0.1:9/token?api=1"
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
      *) a="${a//@ID_TOK@/$ID_TOK}"; a="${a//@REQ_TOK@/$REQ_TOK}"
         a="${a//@ID_PAYLOAD@/${ID_TOK#*.}}"; a="${a//@ID_SIG@/${ID_TOK##*.}}"
         a="${a//@ID_FRAG1@/${ID_TOK:16:12}}"; a="${a//@ID_FRAG2@/${ID_TOK:28:12}}"
         if [[ "$a" == *@ID_SEP@* ]]; then
           sep=""; for ((k = 0; k < ${#ID_TOK}; k += 15)); do sep+="${ID_TOK:k:15}|"; done
           a="${a//@ID_SEP@/$sep}"
         fi
         [[ "$a" == *@ID_B64@* ]] && a="${a//@ID_B64@/$(printf '%s' "$ID_TOK" | base64 -w0)}"
         envs+=("$a") ;;
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
  ck "401: token fetch keeps the URL verbatim"       bash -c "$(declare -f call_block); CD='$CD'; call_block 1 | grep -qx 'ARG https://127.0.0.1:9/token?api=1'"
  ck "401: exchange is a POST"                       bash -c "$(declare -f call_block); CD='$CD'; call_block 2 | grep -A1 -x 'ARG -X' | grep -qx 'ARG POST'"
  ck "401: exchange URL exact"                       bash -c "$(declare -f call_block); CD='$CD'; call_block 2 | grep -qx 'ARG https://registry.npmjs.org/-/npm/v1/oidc/token/exchange/package/@soleur%2fopencode'"
  ck "401: bearer flowed (request token to the fetch)"  grep -qx "BEARER 1 $REQ_TOK" "$CD/bearer.log"
  ck "401: bearer flowed (id-token to the exchange)"    grep -qx "BEARER 2 $ID_TOK" "$CD/bearer.log"
  ck "401: no bearer value in any argv"              not grep -qF -e "$REQ_TOK" -e "$ID_TOK" "$CD/calls.log"
  ck "401: every call has a connect timeout"         test "$(grep -c -x 'ARG --connect-timeout' "$CD/calls.log")" -eq 2
  ck "401: every call has a max time"                test "$(grep -c -x 'ARG --max-time' "$CD/calls.log")" -eq 2
  ck "401: temp dir removed"                         test -z "$(ls -A "$CD/tmp")"
  ck "401: every call pins https only (--proto =https)"  test "$(grep -c -x 'ARG =https' "$CD/calls.log")" -eq 2
  ck "401: every call starts from --disable"         test "$(grep -c -x 'ARG --disable' "$CD/calls.log")" -eq 2
  ck "401: every call sets --noproxy"                test "$(grep -c -x 'ARG --noproxy' "$CD/calls.log")" -eq 2

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
    ck "$c: the registry body is never printed"      not grep -qF -- "$SECRET" "$CD/all"
    ck "$c: curl rc reported"                        grep -qx 'curl_rc=0' "$CD/out"
  done
  run_diag crc28 "STUB_EXCH_CODE=000" "STUB_EXCH_RC=28"
  ck "curl rc 28: registry-error verdict"            verdict_is registry-error
  ck "curl rc 28: exit 0"                            test "$DRC" -eq 0
  ck "curl rc 28: curl_rc reported"                  grep -qx 'curl_rc=28' "$CD/out"

  # --- the id-token could not be obtained ---
  run_diag cnourl "UNSET=ACTIONS_ID_TOKEN_REQUEST_URL"
  ck "no request URL: id-token-missing"              verdict_is id-token-missing
  ck "no request URL: curl never invoked"            test ! -e "$CD/calls.log"
  ck "no request URL: no add-mask line"              not grep -q '^::add-mask::' "$CD/out"
  ck "no request URL: exit 0"                        test "$DRC" -eq 0
  run_diag cnotok "UNSET=ACTIONS_ID_TOKEN_REQUEST_TOKEN"
  ck "no request token: id-token-missing"            verdict_is id-token-missing
  run_diag creqbad 'ACTIONS_ID_TOKEN_REQUEST_TOKEN=a"b'
  ck "request token with a quote: id-token-fetch-failed"  verdict_is id-token-fetch-failed
  ck "request token with a quote: nothing was sent"  test ! -e "$CD/calls.log"
  run_diag creqnl "ACTIONS_ID_TOKEN_REQUEST_TOKEN=$(printf 'abc\ndef')"
  ck "request token with a newline: id-token-fetch-failed"  verdict_is id-token-fetch-failed
  ck "request token with a newline: nothing was sent"  test ! -e "$CD/calls.log"
  run_diag chttp "ACTIONS_ID_TOKEN_REQUEST_URL=http://127.0.0.1:9/token?api=1"
  ck "non-https request URL: id-token-fetch-failed"  verdict_is id-token-fetch-failed
  ck "non-https request URL: nothing was sent"       test ! -e "$CD/calls.log"
  run_diag cctlurl "ACTIONS_ID_TOKEN_REQUEST_URL=https://127.0.0.1:9/a b"
  ck "request URL with a space: id-token-fetch-failed"  verdict_is id-token-fetch-failed
  ck "request URL with a space: nothing was sent"    test ! -e "$CD/calls.log"
  run_diag cnojq "PATH=$NOJQ:$STUBBIN"
  ck "no jq on PATH: registry-error"                 verdict_is registry-error
  ck "no jq on PATH: says so"                        grep -qx 'detail=jq not found on the runner; the id-token response cannot be parsed' "$CD/out"
  ck "no jq on PATH: nothing was sent"               test ! -e "$CD/calls.log"
  run_diag ctmp "TMPDIR=/proc/self/no-such-dir"
  ck "unwritable TMPDIR: id-token-fetch-failed"      verdict_is id-token-fetch-failed
  ck "unwritable TMPDIR: says so"                    grep -qx 'detail=could not create a temp dir' "$CD/out"
  ck "unwritable TMPDIR: nothing was sent"           test ! -e "$CD/calls.log"
  run_diag cfetch500 "STUB_TOK_CODE=500"
  ck "token fetch 500: id-token-fetch-failed"        verdict_is id-token-fetch-failed
  ck "token fetch 500: exchange never attempted"     test "$(calls_total)" -eq 1
  ck "token fetch 500: exit 0"                       test "$DRC" -eq 0
  run_diag cfetchempty "STUB_TOK_BODY={}"
  ck "empty token body: id-token-fetch-failed"       verdict_is id-token-fetch-failed
  run_diag cfetchbad 'STUB_TOK_BODY={"value":"a\"b"}'
  ck "token with a quote: id-token-fetch-failed"     verdict_is id-token-fetch-failed
  ck "token with a quote: no add-mask, no exchange"  test "$(grep -c '^::add-mask::' "$CD/out")$(calls_total)" = "01"

  # --- shapes of the 4xx body that carry no usable message ---
  local b
  for b in '' '<html>nope</html>' '{"message":{"a":1}}' '[]'; do
    run_diag cnomsg "STUB_EXCH_BODY=$b"
    ck "no-message body '$b': trust verdict"         verdict_is trusted-publisher-missing-or-mismatched
    ck "no-message body '$b': falls back to body_bytes"  grep -q '^body_bytes=' "$CD/out"
    ck "no-message body '$b': no message line"       not grep -q '^message=' "$CD/out"
  done
  # A registry that echoes a bearer back must not get it printed (truncation defeats the runner's mask).
  run_diag cechoid 'STUB_EXCH_BODY={"message":"bad @ID_TOK@"}'
  ck "echoed id-token: message dropped"              not grep -q '^message=' "$CD/out"
  ck "echoed id-token: nothing of it printed"        not grep -qF -- "${ID_TOK:16:24}" "$CD/vis"
  run_diag cechoreq 'STUB_EXCH_BODY={"message":"bad @REQ_TOK@"}'
  ck "echoed request token: message dropped"         not grep -q '^message=' "$CD/out"
  ck "echoed request token: nothing of it printed"   not grep -qF -- "$REQ_TOK" "$CD/all"
  run_diag cechopay 'STUB_EXCH_BODY={"message":"bad @ID_PAYLOAD@"}'
  ck "echoed payload+signature: message dropped"     not grep -q '^message=' "$CD/out"
  run_diag cechosig 'STUB_EXCH_BODY={"message":"bad @ID_SIG@"}'
  ck "echoed signature only: message dropped"        not grep -q '^message=' "$CD/out"
  # A control byte inside a bearer fragment is deleted by clean(), which would rejoin the fragment.
  local bs ctl; bs=$'\\'; ctl="${bs}u0001"
  run_diag cechoctl "STUB_EXCH_BODY={\"message\":\"x @ID_FRAG1@${ctl}@ID_FRAG2@\"}"
  ck "bearer split by a control byte: message dropped"  not grep -q '^message=' "$CD/out"
  # A bearer split by separators or newlines, and a re-encoded bearer, must not slip past the window test.
  run_diag cechosep 'STUB_EXCH_BODY={"message":"bad @ID_SEP@"}'
  ck "bearer split every 15 chars by '|': message dropped"  not grep -q '^message=' "$CD/out"
  run_diag cechob64 'STUB_EXCH_BODY={"message":"bad @ID_B64@"}'
  ck "base64-re-encoded bearer: message dropped"     not grep -q '^message=' "$CD/out"
  run_diag clong "STUB_EXCH_BODY={\"message\":\"$(head -c 5000 /dev/zero | tr '\0' A | fold -w 10 | tr '\n' ' ')\"}"
  ck "5 KB message: the printed line is capped"      test "$(grep '^message=' "$CD/out" | awk '{print length($0)}')" -le 210
  # The values the entry must carry follow the run, not a literal.
  run_diag chostile "GITHUB_REPOSITORY=o/r --repo evil/x; id #" "GITHUB_WORKFLOW_REF=o/r/.github/workflows/x;touch pwned;.yml@refs/heads/main"
  ck "hostile repository falls back to the default"  grep -qx 'repository=jikig-ai/soleur' "$CD/out"
  ck "hostile workflow falls back to the default"    grep -qx 'workflow=npm-publish.yml' "$CD/out"
  ck "a fallback is announced, not silent"           grep -q '^detail=the repository and workflow value from the run' "$CD/out"
  run_diag cdotdot "GITHUB_REPOSITORY=../.." "GITHUB_WORKFLOW_REF=o/r/.github/workflows/.yml@refs/heads/main"
  ck "repository '../..' falls back"                 grep -qx 'repository=jikig-ai/soleur' "$CD/out"
  run_diag cdash "GITHUB_REPOSITORY=-x/--allow-publish"
  ck "repository starting with '-' falls back"       grep -qx 'repository=jikig-ai/soleur' "$CD/out"
  run_diag clongrepo "GITHUB_REPOSITORY=$(head -c 120 /dev/zero | tr '\0' a)/$(head -c 120 /dev/zero | tr '\0' b)"
  ck "an over-long fix command is omitted, not truncated"  not grep -q '^fix=' "$CD/out"
  ck "an omitted fix command is announced"           grep -q '^detail=fix command omitted' "$CD/out"
  run_diag cderive "GITHUB_REPOSITORY=acme/widgets" "GITHUB_WORKFLOW_REF=acme/widgets/.github/workflows/pub.yml@refs/heads/main"
  ck "derived repository"                            grep -qx 'repository=acme/widgets' "$CD/out"
  ck "derived workflow"                              grep -qx 'workflow=pub.yml' "$CD/out"
  ck "derived fix command"                           grep -qF -- '--file pub.yml --repo acme/widgets --allow-publish' "$CD/out"

  # --- registry-controlled text must never become a workflow command ---
  local p u2028 u2029 nel del
  u2028="$(printf '\xe2\x80\xa8')"; u2029="$(printf '\xe2\x80\xa9')"; nel="$(printf '\xc2\x85')"; del="$(printf '\x7f')"
  for p in 'x\n::notice::PASS' 'x\r\n::error::boom' 'x%0A::notice::PASS' "x${u2028}::notice::PASS" "x${nel}::notice::PASS" "x${u2029}::notice::PASS" "x${del}::notice::PASS" '::stop-commands::tok' 'x\nNPM_OIDC_VERDICT=exchange-ok'; do
    run_diag cinject "STUB_EXCH_BODY={\"message\":\"$p\"}"
    ck "inject '$p': only allow-listed :: lines"     only_allowed_annotations
    ck "inject '$p': one verdict line"               one_verdict
    ck "inject '$p': still the trust verdict"        verdict_is trusted-publisher-missing-or-mismatched
    ck "inject '$p': no U+2028 in the output"        not env LC_ALL=C grep -q "$u2028" "$CD/out"
    ck "inject '$p': no C1 control in the output"    not env LC_ALL=C grep -q "$nel" "$CD/out"
    ck "inject '$p': no U+2029 in the output"        not env LC_ALL=C grep -q "$u2029" "$CD/out"
    ck "inject '$p': no DEL in the output"           not env LC_ALL=C grep -q "$del" "$CD/out"
  done

  # --- xtrace must not leak a bearer ---
  DIAG_BASH=(bash -x)
  run_diag cxtrace
  DIAG_BASH=(bash)
  ck "xtrace: refused with exit 78"                  test "$DRC" -eq 78
  ck "xtrace: refusal says why"                      grep -qF -- 'refusing to trace' "$CD/all"
  ck "xtrace: id-token not traced"                   not grep -qF -- "$ID_TOK" "$CD/vis"
  ck "xtrace: request token not traced"              not grep -qF -- "$REQ_TOK" "$CD/all"

  # Destination and package are constants: the exact exchange URL and audience are pinned by the 401 block.
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
_seq_before="$B_SEQ"; B_BAD=0; diag_battery "$PRISTINE"; _ctl_bad="$B_BAD"; _ctl_runs=$((B_SEQ - _seq_before - 100))
B_MODE=real
CASES=$((CASES + 1))
# A control that scored 0 because the battery never ran would be vacuous: require the runs.
if [[ "$_ctl_bad" -eq 0 && "$_ctl_runs" -ge 30 ]]; then pass "diagnose: pristine copy scores 0 failing assertions over $_ctl_runs runs (mutant control)"; else fail "diagnose: pristine copy scored $_ctl_bad failing assertions over $_ctl_runs runs (mutant control is red or did not run)"; fi

diag_mutant() { # diag_mutant <label> <sed-script>
  local m="$SANDBOX/diag-mutant-$1.sh"
  assert_fixture_dir "$(dirname "$m")"
  sed "$2" "$PRISTINE" > "$m"; chmod +x "$m"
  if ! bash -n "$m" 2>/dev/null; then
    CASES=$((CASES + 1))
    fail "diagnose mutant '$1': not valid shell (a syntax error is a crash, not a kill)"
    return
  fi
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

diag_mutant leak-id-token      's|^printf .::add-mask::.*|&; echo "leak=$idtok"|'
diag_mutant drop-add-mask      '/^printf .::add-mask::/d'
diag_mutant 401-as-exchange-ok 's/^  2??) /  2??|401|404) /'
diag_mutant 429-as-trust       's/^  401|403|404) /  4??|5??) /'
diag_mutant exit-1-on-verdict  '$ s/^exit 0$/exit 1/'
diag_mutant dispatch-no-curl   's/| curl /| true /'
diag_mutant no-sanitiser       's/^clean() {.*/clean() { printf "%s" "$1"; }/'
diag_mutant no-key-prefix      's/^say() {.*/say() { printf "%s\\n" "$2"; }/'
diag_mutant token-fetch-no-G   's/ -G / /'
diag_mutant no-audience-arg    's/--data-urlencode "audience=[^"]*"//'
diag_mutant keep-xtrace        '/^case "$-" in$/,/^esac$/d;/^set +x$/d'
diag_mutant no-xtrace-refusal  '/^case "$-" in$/,/^esac$/d'
diag_mutant no-2028-strip      's/\\xe2\\x80\[/\\xe2\\x81[/'
diag_mutant no-c1-strip        's/\\xc2\[/\\xc3[/'
diag_mutant no-proto           "s/ --proto '=https'//g"
diag_mutant no-disable         's/curl --disable /curl /g'
diag_mutant no-noproxy         "s/ --noproxy '\\*'//g"
diag_mutant no-reqtok-pattern  '/^if ! \[\[ "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" =~ $TOKPAT \]\]; then$/,/^fi$/d'
diag_mutant no-echo-guard      's/for ((i = 0; i + 16 <= ${#bearers}; i++)); do/for ((i = 0; i + 16 <= 0; i++)); do/'
diag_mutant regerr-dumps-body  's/^    say curl_rc "$xrc"$/&; cat "$tmp\/exchange.json"/'
diag_mutant no-body-bytes      's/say body_bytes/: body_bytes/'
diag_mutant msg-type-unguarded 's/if (.message|type)=="string" then .message else empty end/.message/'
diag_mutant no-https-url-check '/^if ! \[\[ "$ACTIONS_ID_TOKEN_REQUEST_URL" =~ /,/^fi$/d'
diag_mutant no-repo-allowlist  '/^\[\[ "$REPO" =~/d'
diag_mutant no-workflow-allowlist '/^\[\[ "$WORKFLOW" =~/d'
diag_mutant no-jq-branch       '/^if ! command -v jq/,/^fi$/d'
diag_mutant no-2029-strip      's/\\xa8\\xa9/\\xa8/'
diag_mutant no-del-strip       's/\\000-\\037\\177/\\000-\\037/'
diag_mutant raw-window-only    's/\[\[ "$sq" == \*"$w"\* \]\]/[[ "$msg" == *"$w"* ]]/'
diag_mutant no-longrun-rule    's/\[A-Za-z0-9._~+\/=-\]{24}/[A-Za-z0-9._~+\/=-]{240}/'
diag_mutant silent-fallback    '/^    \[\[ -z "$fell_back" \]\] ||/d'
diag_mutant no-fix-length-guard 's/if (( ${#fixcmd} <= 190 )); then/if true; then/'

# ---------------------------------------------------------------------------
# Literals the script restates, pinned to their sources (a rename must red here,
# not print a stale value at failure time).
# ---------------------------------------------------------------------------
CASES=$((CASES + 1))
_pkg_json="$(jq -r .name "$REPO_ROOT/packages/opencode-plugin/package.json" 2>/dev/null)"
_pkg_script="$(sed -n 's/^PACKAGE="\(.*\)"$/\1/p' "$DIAG_SCRIPT")"
if [[ -n "$_pkg_json" && "$_pkg_json" == "$_pkg_script" ]]; then pass "parity: script default package equals packages/opencode-plugin/package.json name"; else fail "parity: script PACKAGE default ($_pkg_script) != package.json name ($_pkg_json)"; fi
CASES=$((CASES + 1))
_rb="$(sed -n 's/^RUNBOOK="\(.*\)"$/\1/p' "$DIAG_SCRIPT")"
if [[ -n "$_rb" && -f "$REPO_ROOT/$_rb" ]]; then pass "parity: the runbook path the script prints exists"; else fail "parity: runbook path '$_rb' printed by the script does not exist"; fi
CASES=$((CASES + 1))
_wf_default="$(sed -n 's/.*; WORKFLOW="\([^"]*\)"; }$/\1/p' "$DIAG_SCRIPT")"
if [[ -n "$_wf_default" && "$_wf_default" == "$(basename "$WF")" ]]; then pass "parity: script default workflow filename equals the real workflow file"; else fail "parity: script WORKFLOW default ($_wf_default) != $(basename "$WF")"; fi

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
# Exact count at the time of writing (296). Slack in a floor is attack budget: raise it in the
# SAME edit that adds an assertion, never in a later tidy-up.
if [[ "$((PASS + FAIL))" -lt 296 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 296." >&2
  exit 1
fi
echo "$PASS passed, $FAIL failed ($((PASS + FAIL)) assertions)"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
# Last line, printed only on a clean run: the discoverability literal. A bare
# `0 failed` substring-matches `10 failed`, so the plan keys on this token.
echo "NPM_PUBLISH_OIDC_SUITE=PASS"
