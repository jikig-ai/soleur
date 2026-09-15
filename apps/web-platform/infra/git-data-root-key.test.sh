#!/usr/bin/env bash
#
# (#8189, ADR-220) Drift-guards for the git-data root-key root and its apply workflow.
#
# WHAT THIS PROTECTS (plan Guard 6 root half, Guard 8, AC5):
#   - apps/web-platform/infra/git-data-root-key/ keeps its DISTINCT state key, prevent_destroy on
#     the five key-bearing addresses, exactly the D-1 address set, the parent's variable names with
#     no default, and none of: output, nonsensitive(, local_file, local-exec, provisioner,
#     terraform_remote_state (the last also across the parent root's *.tf).
#   - .github/workflows/apply-git-data-root-key.yml stays dispatch-only, SHA-pinned, reviewer-gated,
#     serialized on the replace job's `git-data-state` literal with cancel-in-progress `is False`,
#     applies only an additive plan (or the typed read-token rotation), never prints or uploads the
#     plan, shreds it, and emails ops on any non-success.
#   - apply-web-platform-infra.yml's push trigger excludes the root, and infra-validation.yml runs
#     this suite and validates the root.
#
# THE ALLOWLIST IS EXECUTED, NOT RE-DECLARED. The `validate` and `allowlist` step bodies are
# extracted from the workflow by step id (PyYAML) and run under `bash -e` with a PATH-stubbed
# `terraform` that serves synthesized plan-JSON fixtures (cq-test-fixtures-synthesized-only: every
# value below is a fabricated placeholder, never a real key or token).
#
# MUTATION BATTERY (harness convention, modeled on arm-heartbeats.test.sh). Every code-edit row
# copies the file under test, applies a sed edit to the copy, asserts the edit landed on exactly the
# expected deleted/added line counts, points an override at the copy (GD_ROOT_KEY_DIR,
# GD_ROOT_KEY_WORKFLOW, GD_ROOT_KEY_APPLY_WF, GD_ROOT_KEY_PARENT_DIR) and re-runs this suite as a
# child, requiring the NAMED case to print FAIL. Fixture rows run as negative cases.
#
#   row  guard  kind     edit / fixture                                              must go RED
#   F1   G8     fixture  tls_private_key.git_data_root actions ["forget"]            G8.fixture-forget
#   F2   G8     fixture  read-token replace without the typed input                  G8.fixture-rotation-no-input
#   F3   G8     fixture  empty `terraform show -json` output                         G8.fixture-empty-json
#   M1   G8     code     add an output block with nonsensitive( to the root          ROOT.census
#   M2   G8     code     remove the notify-root-key-apply job                         G8.notify-job
#   M3   G6     code     delete cancel-in-progress on the apply job                   G6.apply-cancel-in-progress-false
#   M4   G6     code     move the apply job's group to another name                   G6.apply-group-parity
#   M5   D-1    code     backend key -> the parent's web-platform/terraform.tfstate   ROOT.backend-key
#   M6   D-1    code     prevent_destroy = false on hcloud_ssh_key.git_data_root      ROOT.prevent-destroy.hcloud_ssh_key.git_data_root
#   M7   G8     code     add a push trigger                                           WF.dispatch-only
#   M8   G8     code     unpin setup-terraform to a tag                               WF.sha-pins
#   M9   D-1    code     terraform_remote_state data block in the parent root         PARENT.no-remote-state
#   M10  D-1    code     remove the parent apply's path exclusion                     APPLY.path-exclusion
#   M11  G8     code     widen the jq allowlist to accept ["forget"]                  G8.fixture-forget
#   M12  G8     code     terraform_wrapper: true                                      WF.setup-terraform
#   M13  G8     code     drop -lockfile=readonly from init                            WF.init-readonly-lock
#   M14  D-1    code     ignore_changes on the repo secret                            ROOT.github-secret-no-ignore-changes
#
# Registered in .github/workflows/infra-validation.yml (run: bash <this path>).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../../.." && pwd)"
SELF="${DIR}/$(basename "${BASH_SOURCE[0]}")"

RK_DIR="${GD_ROOT_KEY_DIR:-${DIR}/git-data-root-key}"
PARENT_DIR="${GD_ROOT_KEY_PARENT_DIR:-${DIR}}"
WF="${GD_ROOT_KEY_WORKFLOW:-${ROOT}/.github/workflows/apply-git-data-root-key.yml}"
APPLY_WF="${GD_ROOT_KEY_APPLY_WF:-${ROOT}/.github/workflows/apply-web-platform-infra.yml}"
INFRA_VALIDATION_WF="${ROOT}/.github/workflows/infra-validation.yml"
CHILD="${GD_ROOT_KEY_CHILD:-0}"

MUTANT_FLOOR=17
ASSERT_FLOOR_BASE=74
ASSERT_FLOOR_MUTANTS=30

passes=0
fails=0
skips=0
cases=0
mutants=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; return 0; }

printf '\n=== git-data-root-key ===\n\n'

# ── 0. INSTRUMENT SELF-TEST ────────────────────────────────────────────────────────
# Drive each verdict helper once and require its counter to move by exactly one. A neutered
# pass()/fail() would otherwise make every row below unobservable. Reported directly, never
# through the helpers it is testing.
_st_p=$passes; _st_f=$fails
pass "SELFTEST pass helper" >/dev/null
fail "SELFTEST fail helper" >/dev/null
if [[ "$passes" -ne $((_st_p + 1)) || "$fails" -ne $((_st_f + 1)) ]]; then
  printf '\n[FATAL] instrument self-test: pass()/fail() did not each move their counter by one (passes %d->%d, fails %d->%d).\n' \
    "$_st_p" "$passes" "$_st_f" "$fails" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical, so do not reformat it). Executed as a statement
# before a copy out of an override-supplied tree ($RK_DIR / $PARENT_DIR come from the environment
# in child runs) so the P1b relative-operand ratchet can see the operand is absolute.
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

WORK="$(mktemp -d -t gdrootkey.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

for f in "$WF" "$APPLY_WF" "$INFRA_VALIDATION_WF" "$PARENT_DIR/main.tf" "$PARENT_DIR/.terraform.lock.hcl"; do
  cases=$((cases + 1))
  if [[ -f "$f" ]]; then pass "PRE.file-present: ${f#"$ROOT"/}"; else fail "PRE.file-present: missing $f"; fi
done
cases=$((cases + 1))
if [[ -d "$RK_DIR" && -f "$RK_DIR/.terraform.lock.hcl" ]]; then
  pass "PRE.root-present: root directory and its lock file exist"
else
  fail "PRE.root-present: $RK_DIR or its .terraform.lock.hcl is missing"
fi

cases=$((cases + 1))
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null && command -v jq >/dev/null 2>&1; then
  pass "PRE.tools: python3 + PyYAML + jq available"
else
  fail "PRE.tools: python3 with PyYAML and jq are required — the arms below cannot run and must not read as green"
fi

fact() {  # <facts-var-content> <key> -> value of the first KEY=... line
  awk -v k="$2=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' <<<"$1"
}

# ── 1. THE ROOT (HCL, full-line comments stripped) ─────────────────────────────────
ROOT_FACTS="$(python3 - "$RK_DIR" "$PARENT_DIR" <<'PY' 2>&1
import glob, os, re, sys

rk, parent = sys.argv[1], sys.argv[2]

def strip(text):
    return "\n".join("" if re.match(r"^\s*(#|//)", l) else l for l in text.splitlines())

def code(d):
    files = sorted(glob.glob(os.path.join(d, "*.tf")))
    return files, "\n".join(strip(open(f).read()) for f in files)

def block(text, header_re):
    m = re.search(header_re, text, re.M)
    if not m:
        return None
    i = text.index("{", m.start())
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None

def top_attrs(body):
    out, depth = {}, 0
    for line in body.splitlines():
        s = line.strip()
        if depth == 0:
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', s)
            if m and not m.group(2).endswith("{"):
                out[m.group(1)] = m.group(2).strip()
        depth += line.count("{") - line.count("}")
    return out

def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()

files, t = code(rk)
print("FILES=%d" % len(files))
addrs = sorted("%s.%s" % m for m in re.findall(r'^\s*resource\s+"([a-z0-9_]+)"\s+"([a-z0-9_]+)"', t, re.M))
print("ADDRS=%s" % ",".join(addrs))
print("ADOPT=%d" % len(re.findall(r'^\s*(data|import|moved|removed|module|check)\b', t, re.M)))

backend = block(t, r'^\s*backend\s+"s3"\s*\{') or ""
ba = top_attrs(backend)
print("BACKEND_KEY=%s" % ba.get("key", ""))
print("BACKEND_BUCKET=%s" % ba.get("bucket", ""))
print("BACKEND_KEY_COUNT=%d" % len(re.findall(r'^\s*key\s*=', backend, re.M)))

for addr in ["tls_private_key.git_data_root", "hcloud_ssh_key.git_data_root",
             "doppler_project.git_data_root", "doppler_environment.git_data_root_prd",
             "doppler_secret.git_data_root_ssh_private_key"]:
    ty, nm = addr.split(".")
    b = block(t, r'^\s*resource\s+"%s"\s+"%s"\s*\{' % (ty, nm)) or ""
    lc = block(b, r'^\s*lifecycle\s*\{') or ""
    print("PD_%s=%d" % (addr, 1 if top_attrs(lc).get("prevent_destroy") == "true" else 0))

census = {
    "output": len(re.findall(r'^\s*output\s+"', t, re.M)),
    "nonsensitive": t.count("nonsensitive("),
    "local_file": t.count("local_file"),
    "local-exec": t.count("local-exec"),
    "provisioner": len(re.findall(r'\bprovisioner\b', t)),
    "terraform_remote_state": t.count("terraform_remote_state"),
}
print("CENSUS=%s" % ",".join("%s:%d" % kv for kv in sorted(census.items())))

def res(ty, nm):
    return top_attrs(block(t, r'^\s*resource\s+"%s"\s+"%s"\s*\{' % (ty, nm)) or "")

a = res("tls_private_key", "git_data_root")
print("ATTR_TLS=%s" % a.get("algorithm", ""))
b = block(t, r'^\s*resource\s+"hcloud_ssh_key"\s+"git_data_root"\s*\{') or ""
a = top_attrs(b)
labels = norm(block(b, r'^\s*labels\s*=\s*\{'))
print("ATTR_HKEY=%s|%s|%s" % (a.get("name", ""), a.get("public_key", ""), labels))
a = res("doppler_project", "git_data_root")
print("ATTR_DPROJ=%s" % a.get("name", ""))
a = res("doppler_environment", "git_data_root_prd")
print("ATTR_DENV=%s|%s" % (a.get("slug", ""), a.get("project", "")))
a = res("doppler_secret", "git_data_root_ssh_private_key")
print("ATTR_DSEC=%s|%s|%s|%s|%s" % (a.get("name", ""), a.get("value", ""), a.get("visibility", ""),
                                    a.get("project", ""), a.get("config", "")))
a = res("doppler_service_token", "git_data_root_read")
print("ATTR_DTOK=%s|%s|%s" % (a.get("access", ""), a.get("project", ""), a.get("config", "")))
gb = block(t, r'^\s*resource\s+"github_actions_secret"\s+"doppler_token_git_data_root"\s*\{') or ""
a = top_attrs(gb)
print("ATTR_GHSEC=%s|%s|%s" % (a.get("repository", ""), a.get("secret_name", ""), a.get("plaintext_value", "")))
print("GHSEC_IGNORE_CHANGES=%d" % gb.count("ignore_changes"))

vars_ = re.findall(r'^\s*variable\s+"([a-z0-9_]+)"', t, re.M)
print("VARS=%s" % ",".join(sorted(vars_)))
ndef = nsens = 0
for v in vars_:
    vb = top_attrs(block(t, r'^\s*variable\s+"%s"\s*\{' % v) or "")
    ndef += 1 if "default" in vb else 0
    nsens += 1 if vb.get("sensitive") == "true" else 0
print("VAR_DEFAULTS=%d" % ndef)
print("VAR_SENSITIVE=%d" % nsens)

pfiles, pt = code(parent)
print("PARENT_FILES=%d" % len(pfiles))
print("PARENT_REMOTE_STATE=%d" % pt.count("terraform_remote_state"))
mine = norm(block(t, r'^\s*provider\s+"github"\s*\{'))
theirs = norm(block(strip(open(os.path.join(parent, "main.tf")).read()), r'^\s*provider\s+"github"\s*\{'))
print("GITHUB_PROVIDER_PARITY=%d" % (1 if mine and mine == theirs else 0))

def lockv(path):
    try:
        s = open(path).read()
    except OSError:
        return {}
    return dict(re.findall(r'provider "registry\.terraform\.io/([^"]+)" \{\s*\n\s*version\s*=\s*"([^"]+)"', s))
ml = lockv(os.path.join(rk, ".terraform.lock.hcl"))
pl = lockv(os.path.join(parent, ".terraform.lock.hcl"))
print("LOCK=%s" % ",".join("%s@%s" % kv for kv in sorted(ml.items())))
print("LOCK_PARENT_MISMATCH=%s" % ",".join(sorted(k for k in ml if pl.get(k) != ml[k])))
PY
)" || ROOT_FACTS="PROBE_FAILED=1"

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" PROBE_FAILED)" == "1" || -z "$(fact "$ROOT_FACTS" FILES)" ]]; then
  fail "ROOT.probe: the HCL probe did not run" "$(printf '%s' "$ROOT_FACTS" | tail -3)"
else
  pass "ROOT.probe: the HCL probe ran"
fi

# CENSUS LOWER BOUND, reported directly (never via fail()): a census over zero files bans nothing.
_files="$(fact "$ROOT_FACTS" FILES)"
if [[ "${_files:-0}" -lt 1 ]]; then
  printf '\n[FATAL] root census scanned %s .tf file(s) under %s — a census over nothing is vacuous.\n' "${_files:-0}" "$RK_DIR" >&2
  exit 1
fi

cases=$((cases + 1))
_want_addrs="doppler_environment.git_data_root_prd,doppler_project.git_data_root,doppler_secret.git_data_root_ssh_private_key,doppler_service_token.git_data_root_read,github_actions_secret.doppler_token_git_data_root,hcloud_ssh_key.git_data_root,tls_private_key.git_data_root"
if [[ "$(fact "$ROOT_FACTS" ADDRS)" == "$_want_addrs" ]]; then
  pass "ROOT.address-set: exactly the seven D-1 addresses are declared"
else
  fail "ROOT.address-set: declared addresses differ from D-1" "got: $(fact "$ROOT_FACTS" ADDRS)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ADOPT)" == "0" ]]; then
  pass "ROOT.no-adopt: no data/import/moved/removed/module/check block"
else
  fail "ROOT.no-adopt: $(fact "$ROOT_FACTS" ADOPT) data/import/moved/removed/module/check block(s) in the root"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" BACKEND_KEY)" == '"web-platform/git-data-root-key/terraform.tfstate"' \
      && "$(fact "$ROOT_FACTS" BACKEND_KEY_COUNT)" == "1" \
      && "$(fact "$ROOT_FACTS" BACKEND_BUCKET)" == '"soleur-terraform-state"' ]]; then
  pass "ROOT.backend-key: one backend key, web-platform/git-data-root-key/terraform.tfstate, in soleur-terraform-state"
else
  fail "ROOT.backend-key: backend key/bucket drifted" \
    "key=$(fact "$ROOT_FACTS" BACKEND_KEY) count=$(fact "$ROOT_FACTS" BACKEND_KEY_COUNT) bucket=$(fact "$ROOT_FACTS" BACKEND_BUCKET)"
fi

for _a in tls_private_key.git_data_root hcloud_ssh_key.git_data_root doppler_project.git_data_root \
          doppler_environment.git_data_root_prd doppler_secret.git_data_root_ssh_private_key; do
  cases=$((cases + 1))
  if [[ "$(fact "$ROOT_FACTS" "PD_${_a}")" == "1" ]]; then
    pass "ROOT.prevent-destroy.${_a}: lifecycle prevent_destroy = true"
  else
    fail "ROOT.prevent-destroy.${_a}: prevent_destroy = true is missing from its lifecycle block"
  fi
done

cases=$((cases + 1))
_want_census="local-exec:0,local_file:0,nonsensitive:0,output:0,provisioner:0,terraform_remote_state:0"
if [[ "$(fact "$ROOT_FACTS" CENSUS)" == "$_want_census" ]]; then
  pass "ROOT.census: no output/nonsensitive(/local_file/local-exec/provisioner/terraform_remote_state across ${_files} .tf file(s)"
else
  fail "ROOT.census: a banned construct is present in the root" "$(fact "$ROOT_FACTS" CENSUS)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_TLS)" == '"ED25519"' ]]; then
  pass "ROOT.tls-key: algorithm ED25519"
else
  fail "ROOT.tls-key: algorithm is $(fact "$ROOT_FACTS" ATTR_TLS), want \"ED25519\""
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_HKEY)" == '"soleur-git-data-root"|tls_private_key.git_data_root.public_key_openssh|"soleur-role" = "git-data-root"' ]]; then
  pass "ROOT.hcloud-key: name soleur-git-data-root, public_key from the tls key, labels {soleur-role=git-data-root} only"
else
  fail "ROOT.hcloud-key: name/public_key/labels drifted" "$(fact "$ROOT_FACTS" ATTR_HKEY)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_DPROJ)" == '"soleur-git-data-root"' \
      && "$(fact "$ROOT_FACTS" ATTR_DENV)" == '"prd"|doppler_project.git_data_root.name' ]]; then
  pass "ROOT.doppler-project: isolated project soleur-git-data-root with a prd environment"
else
  fail "ROOT.doppler-project: project/environment drifted" "proj=$(fact "$ROOT_FACTS" ATTR_DPROJ) env=$(fact "$ROOT_FACTS" ATTR_DENV)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_DSEC)" == '"GIT_DATA_ROOT_SSH_PRIVATE_KEY"|tls_private_key.git_data_root.private_key_openssh|"masked"|doppler_project.git_data_root.name|doppler_environment.git_data_root_prd.slug' ]]; then
  pass "ROOT.doppler-secret: GIT_DATA_ROOT_SSH_PRIVATE_KEY = private_key_openssh, masked, in the isolated prd config"
else
  fail "ROOT.doppler-secret: secret shape drifted" "$(fact "$ROOT_FACTS" ATTR_DSEC)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_DTOK)" == '"read"|doppler_project.git_data_root.name|doppler_environment.git_data_root_prd.slug' ]]; then
  pass "ROOT.read-token: access read on the isolated prd config"
else
  fail "ROOT.read-token: service token shape drifted" "$(fact "$ROOT_FACTS" ATTR_DTOK)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" ATTR_GHSEC)" == '"soleur"|"DOPPLER_TOKEN_GIT_DATA_ROOT"|doppler_service_token.git_data_root_read.key' ]]; then
  pass "ROOT.github-secret: repo secret DOPPLER_TOKEN_GIT_DATA_ROOT = the read token's key"
else
  fail "ROOT.github-secret: repo secret shape drifted" "$(fact "$ROOT_FACTS" ATTR_GHSEC)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" GHSEC_IGNORE_CHANGES)" == "0" ]]; then
  pass "ROOT.github-secret-no-ignore-changes: a rotation reaches the repo secret in the same apply"
else
  fail "ROOT.github-secret-no-ignore-changes: ignore_changes on the repo secret would strand a rotated token"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" VARS)" == "doppler_token_tf,github_app_id,github_app_private_key,hcloud_token" \
      && "$(fact "$ROOT_FACTS" VAR_DEFAULTS)" == "0" && "$(fact "$ROOT_FACTS" VAR_SENSITIVE)" == "4" ]]; then
  pass "ROOT.variables: exactly the four prd_terraform names, all sensitive, none defaulted"
else
  fail "ROOT.variables: variable set/defaults/sensitivity drifted" \
    "vars=$(fact "$ROOT_FACTS" VARS) defaults=$(fact "$ROOT_FACTS" VAR_DEFAULTS) sensitive=$(fact "$ROOT_FACTS" VAR_SENSITIVE)"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" GITHUB_PROVIDER_PARITY)" == "1" ]]; then
  pass "ROOT.github-provider: App-auth provider block equals the parent root's"
else
  fail "ROOT.github-provider: provider \"github\" differs from the parent's app_auth block"
fi

cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" LOCK)" == "dopplerhq/doppler@1.21.2,hashicorp/tls@4.3.0,hetznercloud/hcloud@1.63.0,integrations/github@6.12.1" \
      && -z "$(fact "$ROOT_FACTS" LOCK_PARENT_MISMATCH)" ]]; then
  pass "ROOT.lock: doppler 1.21.2, tls 4.3.0, hcloud 1.63.0, github 6.12.1, equal to the parent's lock"
else
  fail "ROOT.lock: locked providers drifted" "lock=$(fact "$ROOT_FACTS" LOCK) parent-mismatch=$(fact "$ROOT_FACTS" LOCK_PARENT_MISMATCH)"
fi

# Parent census lower bound, reported directly.
_pfiles="$(fact "$ROOT_FACTS" PARENT_FILES)"
if [[ "${_pfiles:-0}" -lt 1 ]]; then
  printf '\n[FATAL] parent census scanned %s .tf file(s) under %s.\n' "${_pfiles:-0}" "$PARENT_DIR" >&2
  exit 1
fi
cases=$((cases + 1))
if [[ "$(fact "$ROOT_FACTS" PARENT_REMOTE_STATE)" == "0" ]]; then
  pass "PARENT.no-remote-state: no terraform_remote_state across ${_pfiles} parent .tf file(s)"
else
  fail "PARENT.no-remote-state: the parent root references terraform_remote_state — it would read the root-key state (and the private key) into web-platform plans"
fi

# ── 2. THE WORKFLOW (PyYAML; `on:` read as wf.get(True) or wf.get("on")) ───────────
WF_FACTS="$(python3 - "$WF" "$APPLY_WF" "$INFRA_VALIDATION_WF" "$WORK" <<'PY' 2>&1
import fnmatch, json, os, re, sys, yaml

wf_path, apply_path, iv_path, work = sys.argv[1:5]
raw = open(wf_path).read()
wf = yaml.safe_load(raw)
on = wf.get(True) or wf.get("on") or {}
if isinstance(on, str):
    on = {on: None}
print("ON=%s" % ",".join(sorted(on.keys())))
inputs = ((on.get("workflow_dispatch") or {}).get("inputs") or {})
print("INPUTS=%s" % ",".join(sorted(inputs.keys())))
print("PERMS=%s" % json.dumps(wf.get("permissions"), sort_keys=True))
jobs = wf.get("jobs") or {}
print("JOBS=%s" % ",".join(sorted(jobs.keys())))
wenv = wf.get("env") or {}

apply = jobs.get("apply") or {}
print("APPLY_ENV=%s" % apply.get("environment", ""))
print("APPLY_TIMEOUT=%s" % apply.get("timeout-minutes", ""))
conc = apply.get("concurrency") or {}
print("APPLY_GROUP=%s" % (conc.get("group", "") if isinstance(conc, dict) else ""))
print("APPLY_CIP_IS_FALSE=%d" % (1 if isinstance(conc, dict) and conc.get("cancel-in-progress", None) is False else 0))
print("JOB_PERMS_OK=%d" % (1 if all((j.get("permissions") in (None, {"contents": "read"})) for j in jobs.values()) else 0))

aw = yaml.safe_load(open(apply_path))
rep = ((aw.get("jobs") or {}).get("git_data_host_replace") or {}).get("concurrency") or {}
print("REPLACE_GROUP=%s" % (rep.get("group", "") if isinstance(rep, dict) else ""))

steps = apply.get("steps") or []
def resolve(v):
    v = str(v)
    m = re.fullmatch(r"\$\{\{\s*env\.([A-Z_]+)\s*\}\}", v)
    return str(wenv.get(m.group(1), "")) if m else v
st = [s for s in steps if str(s.get("uses", "")).startswith("hashicorp/setup-terraform@")]
w = (st[0].get("with") or {}) if len(st) == 1 else {}
print("SETUP_TF=%d|%s|%d" % (len(st), resolve(w.get("terraform_version", "")),
                              1 if w.get("terraform_wrapper", None) is False else 0))

runs = [str(s.get("run", "")) for j in jobs.values() for s in (j.get("steps") or [])]
init = [r for r in runs if re.search(r"\bterraform init\b", r)]
print("INIT_READONLY=%d" % (1 if init and all("-lockfile=readonly" in r and "-input=false" in r for r in init) else 0))
plan_out = [r for r in runs if re.search(r"terraform plan\b[^\n]*-out \"\$RUNNER_TEMP/tfplan\"", r)]
applyr = [r for r in runs if re.search(r"terraform apply\b[^\n]*\"\$RUNNER_TEMP/tfplan\"", r)]
print("PLAN_APPLY_SAVED=%d|%d" % (len(plan_out), len(applyr)))

show_lines = [l for r in runs for l in r.splitlines() if re.search(r"\bterraform show\b", l)]
piped = [l for l in show_lines if re.search(r"terraform show -json [^|]*\|\s*jq\b", l)]
print("SHOW=%d|%d" % (len(show_lines), len(piped)))

code_lines = [l for l in raw.splitlines() if not re.match(r"^\s*#", l)]
code = "\n".join(code_lines)
bans = {
    "upload-artifact": code.count("upload-artifact"),
    "terraform_output": len(re.findall(r"\bterraform output\b", code)),
    "TF_LOG": code.count("TF_LOG"),
    "run_inputs_interp": sum(r.count("${{ inputs.") for r in runs),
}
print("BANS=%s" % ",".join("%s:%d" % kv for kv in sorted(bans.items())))

uses = [l for l in code_lines if re.match(r"^\s*(-\s+)?uses:\s*", l)]
remote = [l for l in uses if not re.search(r"uses:\s*\./", l)]
pinned = [l for l in remote if re.search(r"uses:\s*[^@\s]+@[0-9a-f]{40} # v", l)]
print("PINS=%d|%d" % (len(remote), len(pinned)))

shred = [s for s in steps if "always()" in str(s.get("if", "")) and "shred" in str(s.get("run", ""))
         and "$RUNNER_TEMP/tfplan" in str(s.get("run", ""))]
print("SHRED=%d" % len(shred))

val = next((s for s in steps if s.get("id") == "validate"), None)
print("VALIDATE_FIRST=%d" % (1 if steps and steps[0] is val else 0))
venv = (val or {}).get("env") or {}
print("CONFIRM_ENV=%d" % (1 if venv.get("CONFIRM_RAW") == "${{ inputs.confirm }}"
                            and venv.get("ROTATE_RAW") == "${{ inputs.rotate_read_token }}"
                            and '"APPLY-GIT-DATA-ROOT-KEY"' in str((val or {}).get("run", "")) else 0))
if val:
    open(os.path.join(work, "validate.sh"), "w").write(str(val.get("run", "")))
al = next((s for s in steps if s.get("id") == "allowlist"), None)
if al:
    body = str(al.get("run", ""))
    open(os.path.join(work, "allowlist.sh"), "w").write(body)
    m = re.search(r"<<'JQ'\n(.*?)\nJQ\n", body, re.S)
    prog = m.group(1) if m else ""
    prog_nostr = re.sub(r'"(?:[^"\\]|\\.)*"', '""', prog)
    fields = sorted(set(re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", prog_nostr)))
    print("JQ_FIELDS=%s" % ",".join(fields))
    ai = [i for i, s in enumerate(steps) if s is al][0]
    ap = [i for i, s in enumerate(steps) if re.search(r"terraform apply\b", str(s.get("run", "")))]
    print("ALLOWLIST_BEFORE_APPLY=%d" % (1 if ap and all(ai < i for i in ap) else 0))

notify = jobs.get("notify-root-key-apply") or {}
needs = notify.get("needs") or []
needs = [needs] if isinstance(needs, str) else needs
ifx = str(notify.get("if", ""))
nsteps = notify.get("steps") or []
mail = [s for s in nsteps if s.get("uses") == "./.github/actions/notify-ops-email"
        and (s.get("with") or {}).get("resend-api-key") == "${{ secrets.RESEND_API_KEY }}"]
print("NOTIFY=%d|%d|%d|%d|%d" % (1 if notify else 0, 1 if "apply" in needs else 0,
      1 if ("always()" in ifx and "needs.apply.result != 'success'" in ifx) else 0,
      1 if "environment" not in notify else 0, len(mail)))

# Parent apply's push paths, evaluated IN ORDER (later patterns override earlier ones).
aon = aw.get(True) or aw.get("on") or {}
paths = [str(p) for p in (((aon.get("push") or {}).get("paths")) or [])]
def routes(path):
    hit = False
    for p in paths:
        neg = p.startswith("!")
        if fnmatch.fnmatch(path, p[1:] if neg else p):
            hit = not neg
    return hit
print("EXCL=%d|%d|%d" % (1 if "!apps/web-platform/infra/git-data-root-key/**" in paths else 0,
                         0 if routes("apps/web-platform/infra/git-data-root-key/key.tf") else 1,
                         1 if routes("apps/web-platform/infra/git-data.tf") else 0))

iv = yaml.safe_load(open(iv_path))
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
reg = [s for s in ivsteps if str(s.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-root-key.test.sh"]
vs = [s for s in ivsteps if s.get("working-directory") == "apps/web-platform/infra/git-data-root-key"
      and "terraform init -backend=false" in str(s.get("run", "")) and "terraform validate" in str(s.get("run", ""))
      and str((s.get("env") or {}).get("TF_DATA_DIR", "")).startswith("${{ runner.temp }}")]
print("IV=%d|%d" % (len(reg), len(vs)))
PY
)" || WF_FACTS="PROBE_FAILED=1"

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" PROBE_FAILED)" == "1" || -z "$(fact "$WF_FACTS" JOBS)" ]]; then
  fail "WF.probe: the workflow probe did not run" "$(printf '%s' "$WF_FACTS" | tail -3)"
else
  pass "WF.probe: the workflow probe ran"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" ON)" == "workflow_dispatch" ]]; then
  pass "WF.dispatch-only: the only trigger is workflow_dispatch (no push)"
else
  fail "WF.dispatch-only: triggers are '$(fact "$WF_FACTS" ON)' — a push-queued approval would hold git-data-state"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" INPUTS)" == "confirm,rotate_read_token" ]]; then
  pass "WF.inputs: exactly {confirm, rotate_read_token}"
else
  fail "WF.inputs: input set is '$(fact "$WF_FACTS" INPUTS)'"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" PERMS)" == '{"contents": "read"}' && "$(fact "$WF_FACTS" JOB_PERMS_OK)" == "1" ]]; then
  pass "WF.permissions: contents: read (workflow and every job)"
else
  fail "WF.permissions: permissions widened" "workflow=$(fact "$WF_FACTS" PERMS) jobs_ok=$(fact "$WF_FACTS" JOB_PERMS_OK)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" JOBS)" == "apply,notify-root-key-apply" ]]; then
  pass "WF.jobs: exactly {apply, notify-root-key-apply}"
else
  fail "WF.jobs: job set is '$(fact "$WF_FACTS" JOBS)'"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" APPLY_ENV)" == "web-platform-infra-apply" && "$(fact "$WF_FACTS" APPLY_TIMEOUT)" == "20" ]]; then
  pass "WF.apply-gate: apply job has environment web-platform-infra-apply and timeout-minutes 20"
else
  fail "WF.apply-gate: environment/timeout drifted" "env=$(fact "$WF_FACTS" APPLY_ENV) timeout=$(fact "$WF_FACTS" APPLY_TIMEOUT)"
fi

_rep_group="$(fact "$WF_FACTS" REPLACE_GROUP)"
cases=$((cases + 1))
if [[ -n "$_rep_group" && "$(fact "$WF_FACTS" APPLY_GROUP)" == "$_rep_group" ]]; then
  pass "G6.apply-group-parity: apply job group equals git_data_host_replace's literal ($_rep_group)"
else
  fail "G6.apply-group-parity: apply group '$(fact "$WF_FACTS" APPLY_GROUP)' != replace group '${_rep_group:-<none extracted>}'" \
    "GitHub does not error on divergent group strings; they silently fail to serialize"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" APPLY_CIP_IS_FALSE)" == "1" ]]; then
  pass "G6.apply-cancel-in-progress-false: cancel-in-progress is False on the apply job"
else
  fail "G6.apply-cancel-in-progress-false: cancel-in-progress is not the boolean False on the apply job"
fi

cases=$((cases + 1))
_pins="$(fact "$WF_FACTS" PINS)"
if [[ "${_pins%%|*}" -ge 3 && "${_pins%%|*}" == "${_pins##*|}" ]]; then
  pass "WF.sha-pins: every remote uses: matches @<40-hex> # v (${_pins%%|*} sites)"
else
  fail "WF.sha-pins: remote uses: sites vs SHA-pinned = ${_pins/|/ vs }"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" SETUP_TF)" == "1|1.10.5|1" ]]; then
  pass "WF.setup-terraform: one setup-terraform, terraform_version 1.10.5, terraform_wrapper False"
else
  fail "WF.setup-terraform: setup-terraform drifted (count|version|wrapper_false)" "$(fact "$WF_FACTS" SETUP_TF)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" INIT_READONLY)" == "1" ]]; then
  pass "WF.init-readonly-lock: every terraform init uses -input=false -lockfile=readonly"
else
  fail "WF.init-readonly-lock: a terraform init without -lockfile=readonly/-input=false"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" PLAN_APPLY_SAVED)" == "1|1" && "$(fact "$WF_FACTS" ALLOWLIST_BEFORE_APPLY)" == "1" ]]; then
  pass "WF.saved-plan: plan -out \$RUNNER_TEMP/tfplan, the allowlist step runs before the one apply of that saved plan"
else
  fail "WF.saved-plan: plan/apply/allowlist ordering drifted" \
    "plan|apply=$(fact "$WF_FACTS" PLAN_APPLY_SAVED) allowlist_before_apply=$(fact "$WF_FACTS" ALLOWLIST_BEFORE_APPLY)"
fi

cases=$((cases + 1))
_show="$(fact "$WF_FACTS" SHOW)"
if [[ "${_show%%|*}" -ge 1 && "${_show%%|*}" == "${_show##*|}" ]]; then
  pass "G8.show-piped: every terraform show is -json piped straight into jq (${_show%%|*} site(s))"
else
  fail "G8.show-piped: terraform show sites vs piped-into-jq = ${_show/|/ vs }" "a stdout terraform show prints the private key"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" BANS)" == "TF_LOG:0,run_inputs_interp:0,terraform_output:0,upload-artifact:0" ]]; then
  pass "G8.census: no upload-artifact, terraform output, TF_LOG, or \${{ inputs. }} inside a run body"
else
  fail "G8.census: a banned construct is present in the workflow" "$(fact "$WF_FACTS" BANS)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" SHRED)" -ge 1 ]]; then
  pass "G8.shred: an if: always() step shreds \$RUNNER_TEMP/tfplan"
else
  fail "G8.shred: no if: always() step shreds \$RUNNER_TEMP/tfplan"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" VALIDATE_FIRST)" == "1" && "$(fact "$WF_FACTS" CONFIRM_ENV)" == "1" ]]; then
  pass "WF.confirm: the validate step runs first and receives both inputs through env:"
else
  fail "WF.confirm: input validation is not first or does not route inputs through env:" \
    "first=$(fact "$WF_FACTS" VALIDATE_FIRST) env=$(fact "$WF_FACTS" CONFIRM_ENV)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" JQ_FIELDS)" == "actions,address,change,resource_changes" ]]; then
  pass "G8.jq-fields: the allowlist program reads only resource_changes[].address and .change.actions"
else
  fail "G8.jq-fields: the allowlist program reads fields beyond address/actions" "fields=$(fact "$WF_FACTS" JQ_FIELDS)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" NOTIFY)" == "1|1|1|1|1" ]]; then
  pass "G8.notify-job: notify-root-key-apply needs apply, fires on always() && result != success, no environment, emails via notify-ops-email"
else
  fail "G8.notify-job: the failure-notice job is missing or drifted (present|needs|if|no-env|mail)" "$(fact "$WF_FACTS" NOTIFY)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" EXCL)" == "1|1|1" ]]; then
  pass "APPLY.path-exclusion: the parent push apply excludes apps/web-platform/infra/git-data-root-key/** (and still routes git-data.tf)"
else
  fail "APPLY.path-exclusion: apply-web-platform-infra.yml push paths do not exclude the root (literal|excluded|control)" "$(fact "$WF_FACTS" EXCL)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" IV)" == "1|1" ]]; then
  pass "IV.registered: infra-validation.yml runs this suite (run: bash <path>) and validates the root with TF_DATA_DIR under runner.temp"
else
  fail "IV.registered: registration|validate-step counts in infra-validation.yml" "$(fact "$WF_FACTS" IV)"
fi

# ── 3. EXECUTED STEP BODIES ────────────────────────────────────────────────────────
STUB="$WORK/bin"
mkdir -p "$STUB"
cat > "$STUB/terraform" <<'SH'
#!/usr/bin/env bash
# Synthesized-fixture stub: serves $FIXTURE for `terraform show -json <plan>` only.
if [[ "${1:-}" == "show" && "${2:-}" == "-json" ]]; then
  [[ "${STUB_SHOW_RC:-0}" -eq 0 ]] || exit "$STUB_SHOW_RC"
  cat "$FIXTURE"
  exit 0
fi
echo "terraform stub: unexpected invocation: $*" >&2
exit 64
SH
chmod +x "$STUB/terraform"

run_validate() {  # <confirm> <rotate> -> sets V_RC V_OUT
  V_OUT="$(cd "$WORK" && env CONFIRM_RAW="$1" ROTATE_RAW="$2" bash -e "$WORK/validate.sh" 2>&1)"
  V_RC=$?
}

run_allowlist() {  # <fixture-file> <rotate-raw> [show-rc] -> sets A_RC A_OUT
  A_OUT="$(cd "$WORK" && env PATH="$STUB:$PATH" FIXTURE="$1" ROTATE_RAW="$2" STUB_SHOW_RC="${3:-0}" \
             RUNNER_TEMP="$WORK" bash -e "$WORK/allowlist.sh" 2>&1)"
  A_RC=$?
}

SENT="SYNTHETIC-SENTINEL-not-a-key-0000"
fixture() {  # <name> <json-resource_changes-array> -> path
  local p="$WORK/fx-$1.json"
  printf '{"format_version":"1.2","variables":{"hcloud_token":{"value":"%s"}},"resource_changes":%s,"prior_state":{"values":{"root_module":{"resources":[{"values":{"private_key_openssh":"%s"}}]}}}}\n' \
    "$SENT" "$2" "$SENT" > "$p"
  printf '%s' "$p"
}
rc_entry() {  # <address> <actions-json>
  printf '{"address":"%s","mode":"managed","change":{"actions":%s,"after":{"value":"%s"}}}' "$1" "$2" "$SENT"
}
all7() {  # <actions-json for every address> [override-address override-actions]...
  local acts="$1"; shift
  local out="" a act
  for a in tls_private_key.git_data_root hcloud_ssh_key.git_data_root doppler_project.git_data_root \
           doppler_environment.git_data_root_prd doppler_secret.git_data_root_ssh_private_key \
           doppler_service_token.git_data_root_read github_actions_secret.doppler_token_git_data_root; do
    act="$acts"
    local i=1
    while [[ $i -le $# ]]; do
      local k="${!i}"; local j=$((i + 1)); local v="${!j}"
      [[ "$k" == "$a" ]] && act="$v"
      i=$((i + 2))
    done
    out="${out:+$out,}$(rc_entry "$a" "$act")"
  done
  printf '[%s]' "$out"
}

if [[ ! -s "$WORK/validate.sh" || ! -s "$WORK/allowlist.sh" ]]; then
  cases=$((cases + 1)); fail "G8.extract: could not extract the validate/allowlist step bodies by id"
else
  cases=$((cases + 1)); pass "G8.extract: validate and allowlist step bodies extracted by step id"
fi

# validate step
run_validate "APPLY-GIT-DATA-ROOT-KEY" ""
cases=$((cases + 1))
[[ "$V_RC" -eq 0 ]] && pass "WF.validate-accepts: exact confirm, empty rotate -> rc 0" \
  || fail "WF.validate-accepts: exact confirm rejected (rc=$V_RC)" "$V_OUT"
run_validate "APPLY-GIT-DATA-ROOT-KEY" "ROTATE-GIT-DATA-ROOT-READ-TOKEN"
cases=$((cases + 1))
[[ "$V_RC" -eq 0 ]] && pass "WF.validate-rotate-exact: exact rotate literal -> rc 0" \
  || fail "WF.validate-rotate-exact: exact rotate literal rejected (rc=$V_RC)" "$V_OUT"
for _bad in "apply-git-data-root-key" "APPLY-GIT-DATA-ROOT-KEY " "" "REHEARSE-GIT-DATA"; do
  run_validate "$_bad" ""
  cases=$((cases + 1))
  [[ "$V_RC" -ne 0 ]] && pass "WF.validate-rejects-confirm: '${_bad}' -> refused" \
    || fail "WF.validate-rejects-confirm: '${_bad}' accepted as confirm"
done
run_validate "APPLY-GIT-DATA-ROOT-KEY" "rotate"
cases=$((cases + 1))
[[ "$V_RC" -ne 0 ]] && pass "WF.validate-rejects-rotate-typo: a non-empty, non-exact rotate input -> refused" \
  || fail "WF.validate-rejects-rotate-typo: rotate typo accepted"

# allowlist step
_ok() {  # <case-id> <desc> <fixture> <rotate>
  run_allowlist "$3" "$4"
  cases=$((cases + 1))
  if [[ "$A_RC" -eq 0 && "${A_OUT%%$'\n'*}" == "verdict=ok" && "$A_OUT" != *"$SENT"* ]]; then
    pass "$1: $2 -> verdict=ok"
  else
    fail "$1: $2 -> expected verdict=ok (rc=$A_RC)" "$(printf '%s' "$A_OUT" | head -3)"
  fi
}
_refused() {  # <case-id> <desc> <fixture> <rotate> <verdict> [expected-line] [matrix-row]
  run_allowlist "$3" "$4" "${8:-0}"
  cases=$((cases + 1))
  if [[ "$A_RC" -ne 0 && "$A_OUT" == *"verdict=$5"* && ( -z "${6:-}" || "$A_OUT" == *"$6"* ) && "$A_OUT" != *"$SENT"* ]]; then
    pass "$1: $2 -> refused verdict=$5"
    [[ "${7:-}" == "row" ]] && mutants=$((mutants + 1))
  else
    fail "$1: $2 -> expected refusal verdict=$5 (rc=$A_RC)" "$(printf '%s' "$A_OUT" | head -3)"
  fi
}

_ok "G8.allow-create-only" "all seven addresses create" "$(fixture create "$(all7 '["create"]')")" ""
_ok "G8.allow-noop-read" "no-op everywhere, one read" \
  "$(fixture noopread "$(all7 '["no-op"]' tls_private_key.git_data_root '["read"]')")" ""
_ok "G8.rotation-typed-ok" "typed rotation: token replace + secret update, all else no-op" \
  "$(fixture rot "$(all7 '["no-op"]' doppler_service_token.git_data_root_read '["delete","create"]' github_actions_secret.doppler_token_git_data_root '["update"]')")" \
  "ROTATE-GIT-DATA-ROOT-READ-TOKEN"

_refused "G8.fixture-forget" "tls_private_key.git_data_root forget" \
  "$(fixture forget "$(all7 '["no-op"]' tls_private_key.git_data_root '["forget"]')")" "" \
  git_data_root_key_non_additive "refused tls_private_key.git_data_root forget" row
_refused "G8.fixture-rotation-no-input" "token replace without the typed input" "$WORK/fx-rot.json" "" \
  git_data_root_key_non_additive "refused doppler_service_token.git_data_root_read delete,create" row
: > "$WORK/fx-empty.json"
_refused "G8.fixture-empty-json" "empty show -json output" "$WORK/fx-empty.json" "" \
  git_data_root_key_plan_unreadable "" row

_refused "G8.rotation-typed-other-update" "typed rotation plus an update elsewhere" \
  "$(fixture rotupd "$(all7 '["no-op"]' doppler_service_token.git_data_root_read '["delete","create"]' hcloud_ssh_key.git_data_root '["update"]')")" \
  "ROTATE-GIT-DATA-ROOT-READ-TOKEN" git_data_root_key_non_additive "refused hcloud_ssh_key.git_data_root update"
_refused "G8.rotation-typed-other-create" "typed rotation plus a create elsewhere" \
  "$(fixture rotcre "$(all7 '["no-op"]' doppler_service_token.git_data_root_read '["delete","create"]' tls_private_key.git_data_root '["create"]')")" \
  "ROTATE-GIT-DATA-ROOT-READ-TOKEN" git_data_root_key_non_additive "refused tls_private_key.git_data_root create"
_refused "G8.rotation-typed-token-forget" "typed rotation that forgets the token" \
  "$(fixture rotfor "$(all7 '["no-op"]' doppler_service_token.git_data_root_read '["forget"]')")" \
  "ROTATE-GIT-DATA-ROOT-READ-TOKEN" git_data_root_key_non_additive "refused doppler_service_token.git_data_root_read forget"
_refused "G8.rotation-typo-not-rotation" "rotation plan with a mistyped input" "$WORK/fx-rot.json" "rotate" \
  git_data_root_key_non_additive
_refused "G8.fixture-delete" "hcloud_ssh_key.git_data_root delete" \
  "$(fixture del "$(all7 '["no-op"]' hcloud_ssh_key.git_data_root '["delete"]')")" "" git_data_root_key_non_additive \
  "refused hcloud_ssh_key.git_data_root delete"
_refused "G8.fixture-update" "doppler_secret update" \
  "$(fixture upd "$(all7 '["no-op"]' doppler_secret.git_data_root_ssh_private_key '["update"]')")" "" \
  git_data_root_key_non_additive "refused doppler_secret.git_data_root_ssh_private_key update"
_refused "G8.fixture-replace" "tls key create-before-destroy replace" \
  "$(fixture repl "$(all7 '["no-op"]' tls_private_key.git_data_root '["create","delete"]')")" "" \
  git_data_root_key_non_additive "refused tls_private_key.git_data_root create,delete"
printf '{"resource_changes": [' > "$WORK/fx-invalid.json"
_refused "G8.fixture-invalid-json" "truncated JSON" "$WORK/fx-invalid.json" "" git_data_root_key_plan_unreadable
printf '{"format_version":"1.2"}\n' > "$WORK/fx-nochanges.json"
_refused "G8.fixture-no-resource-changes" "no resource_changes key" "$WORK/fx-nochanges.json" "" git_data_root_key_plan_unreadable
_refused "G8.fixture-empty-resource-changes" "resource_changes: []" "$(fixture emptyrc '[]')" "" git_data_root_key_plan_unreadable
_refused "G8.fixture-actions-not-array" "actions as a bare string" \
  "$(fixture strAct '[{"address":"tls_private_key.git_data_root","change":{"actions":"create"}}]')" "" git_data_root_key_plan_unreadable
_refused "G8.fixture-show-fails" "terraform show exits non-zero" "$WORK/fx-create.json" "" git_data_root_key_plan_unreadable "" "" 1

# ── 4. MUTATION BATTERY (parent run only) ──────────────────────────────────────────
MUTANT=""
mutate() {  # <name> <src-file> <want del/add> <sed-expr> [dir-kind: root|parent] -> sets MUTANT (file or dir)
  local name="$1" src="$2" want="$3" expr="$4" kind="${5:-}"
  local dst target del add
  if [[ -z "$kind" ]]; then
    dst="$WORK/mut-$name-$(basename "$src")"
    cp "$src" "$dst" || { printf '[FATAL] mutation copy failed for %s\n' "$name" >&2; exit 2; }
    target="$dst"; MUTANT="$dst"
  else
    dst="$WORK/mut-$name"
    mkdir -p "$dst"
    if [[ "$kind" == "root" ]]; then
      assert_fixture_dir "$RK_DIR"
      cp "$RK_DIR"/*.tf "$RK_DIR"/.terraform.lock.hcl "$dst"/ || { printf '[FATAL] root copy failed\n' >&2; exit 2; }
    else
      assert_fixture_dir "$PARENT_DIR"
      cp "$PARENT_DIR"/*.tf "$PARENT_DIR"/.terraform.lock.hcl "$dst"/ || { printf '[FATAL] parent copy failed\n' >&2; exit 2; }
    fi
    target="$dst/$(basename "$src")"; MUTANT="$dst"
  fi
  sed -i "$expr" "$target" || { printf '[FATAL] sed failed for %s\n' "$name" >&2; exit 2; }
  del=$(diff "$src" "$target" | grep -c '^<' || true)
  add=$(diff "$src" "$target" | grep -c '^>' || true)
  cases=$((cases + 1))
  if [[ "$del/$add" == "$want" ]]; then
    pass "MUT.$name: edit landed on exactly $want (deleted/added) line(s) of a pristine copy"
    return 0
  fi
  fail "MUT.$name: edit landed on $del/$add line(s), want $want" "sed [$expr] — the row would not test what its title says"
  return 1
}

expect_red() {  # <name> <case-id> <VAR=path>...
  local name="$1" id="$2"; shift 2
  local out rc
  out="$(env GD_ROOT_KEY_CHILD=1 "$@" bash "$SELF" 2>&1)"
  rc=$?
  cases=$((cases + 1))
  if [[ "$rc" -ne 0 ]] && grep -qE "^  FAIL ${id//./\\.}:" <<<"$out"; then
    pass "MUT.$name: the named case ${id} went RED"
    mutants=$((mutants + 1))
  else
    fail "MUT.$name: the named case ${id} did NOT go RED (rc=$rc)" "$(grep -E '^  FAIL' <<<"$out" | head -3)"
  fi
}

if [[ "$CHILD" != "1" ]]; then
  # CONTROL: pristine copies through every override must stay fully green, or a red baseline is
  # indistinguishable from a caught mutation.
  mkdir -p "$WORK/ctl-root" "$WORK/ctl-parent"
  assert_fixture_dir "$RK_DIR"; assert_fixture_dir "$PARENT_DIR"
  cp "$RK_DIR"/*.tf "$RK_DIR"/.terraform.lock.hcl "$WORK/ctl-root/"
  cp "$PARENT_DIR"/*.tf "$PARENT_DIR"/.terraform.lock.hcl "$WORK/ctl-parent/"
  cp "$WF" "$WORK/ctl-wf.yml"; cp "$APPLY_WF" "$WORK/ctl-apply.yml"
  _ctl_out="$(env GD_ROOT_KEY_CHILD=1 GD_ROOT_KEY_DIR="$WORK/ctl-root" GD_ROOT_KEY_PARENT_DIR="$WORK/ctl-parent" \
                GD_ROOT_KEY_WORKFLOW="$WORK/ctl-wf.yml" GD_ROOT_KEY_APPLY_WF="$WORK/ctl-apply.yml" bash "$SELF" 2>&1)"
  _ctl_rc=$?
  cases=$((cases + 1))
  if [[ "$_ctl_rc" -eq 0 ]] && grep -qE '^=== git-data-root-key: [0-9]+ passed, 0 failed, 0 skipped ===$' <<<"$_ctl_out"; then
    pass "MUT.control: unmutated copies through every override run fully green"
  else
    fail "MUT.control: the unmutated child run is not green (rc=$_ctl_rc)" "$(grep -E '^  FAIL|FATAL' <<<"$_ctl_out" | head -3)"
  fi

  # M1 root output + nonsensitive(
  if mutate root-output "$RK_DIR/key.tf" "0/1" '$a output "leak" { value = nonsensitive(tls_private_key.git_data_root.private_key_openssh) }' root; then
    expect_red root-output ROOT.census GD_ROOT_KEY_DIR="$MUTANT"
  fi
  # M2 remove the notify job (from its key to EOF; it is the last job)
  _notify_lines=$(awk '/^  notify-root-key-apply:$/{f=1} f' "$WF" | wc -l)
  cases=$((cases + 1))
  if [[ "$_notify_lines" -ge 5 ]] && [[ "$(tail -n +"$(grep -n '^  notify-root-key-apply:$' "$WF" | cut -d: -f1)" "$WF" | grep -c '^  [a-z][a-z0-9_-]*:$')" -eq 1 ]]; then
    pass "MUT.notify-removal-shape: notify-root-key-apply is the last job (${_notify_lines} lines)"
  else
    fail "MUT.notify-removal-shape: notify-root-key-apply is not the last job or is too short (${_notify_lines} lines)"
  fi
  if mutate notify-removed "$WF" "${_notify_lines}/0" '/^  notify-root-key-apply:$/,$d'; then
    expect_red notify-removed G8.notify-job GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M3 delete cancel-in-progress
  if mutate cancel-deleted "$WF" "1/0" '/^      cancel-in-progress: false$/d'; then
    expect_red cancel-deleted G6.apply-cancel-in-progress-false GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M4 group renamed
  if mutate group-renamed "$WF" "1/1" 's/^      group: git-data-state$/      group: git-data-root-key/'; then
    expect_red group-renamed G6.apply-group-parity GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M5 backend key -> the parent's
  if mutate backend-key "$RK_DIR/main.tf" "1/1" 's|"web-platform/git-data-root-key/terraform.tfstate"|"web-platform/terraform.tfstate"|' root; then
    expect_red backend-key ROOT.backend-key GD_ROOT_KEY_DIR="$MUTANT"
  fi
  # M6 prevent_destroy false on the Hetzner key object
  if mutate prevent-destroy "$RK_DIR/key.tf" "1/1" '/^resource "hcloud_ssh_key" "git_data_root"/,/^}/ s/prevent_destroy = true/prevent_destroy = false/' root; then
    expect_red prevent-destroy ROOT.prevent-destroy.hcloud_ssh_key.git_data_root GD_ROOT_KEY_DIR="$MUTANT"
  fi
  # M7 push trigger
  if mutate push-trigger "$WF" "0/2" 's/^  workflow_dispatch:$/  push:\n    branches: [main]\n  workflow_dispatch:/'; then
    expect_red push-trigger WF.dispatch-only GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M8 unpinned setup-terraform
  if mutate unpinned "$WF" "1/1" 's|hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0|hashicorp/setup-terraform@v4 # v4.0.0|'; then
    expect_red unpinned WF.sha-pins GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M9 terraform_remote_state in the parent
  if mutate parent-remote-state "$PARENT_DIR/main.tf" "0/1" '$a data "terraform_remote_state" "git_data_root_key" { backend = "s3" }' parent; then
    expect_red parent-remote-state PARENT.no-remote-state GD_ROOT_KEY_PARENT_DIR="$MUTANT"
  fi
  # M10 path exclusion removed
  if mutate exclusion-removed "$APPLY_WF" "1/0" '\|^      - "!apps/web-platform/infra/git-data-root-key/\*\*"$|d'; then
    expect_red exclusion-removed APPLY.path-exclusion GD_ROOT_KEY_APPLY_WF="$MUTANT"
  fi
  # M11 jq allowlist widened to accept forget
  if mutate jq-forget "$WF" "1/1" 's/def base_ok: \. == \["no-op"\] or/def base_ok: . == ["forget"] or . == ["no-op"] or/'; then
    expect_red jq-forget G8.fixture-forget GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M12 terraform_wrapper true
  if mutate wrapper-true "$WF" "1/1" 's/^          terraform_wrapper: false$/          terraform_wrapper: true/'; then
    expect_red wrapper-true WF.setup-terraform GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M13 -lockfile=readonly dropped
  if mutate no-readonly "$WF" "1/1" 's/terraform init -input=false -lockfile=readonly$/terraform init -input=false/'; then
    expect_red no-readonly WF.init-readonly-lock GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M14 ignore_changes on the repo secret
  if mutate ignore-changes "$RK_DIR/access.tf" "0/3" 's/^  plaintext_value = doppler_service_token\.git_data_root_read\.key$/&\n  lifecycle {\n    ignore_changes = [plaintext_value]\n  }/' root; then
    expect_red ignore-changes ROOT.github-secret-no-ignore-changes GD_ROOT_KEY_DIR="$MUTANT"
  fi

  # MUTANT FLOOR, reported directly: every matrix row (3 fixture + 14 code) must have gone RED.
  if [[ "$mutants" -lt "$MUTANT_FLOOR" ]]; then
    printf '\n[FATAL] mutant floor: %d of %d matrix rows went RED.\n' "$mutants" "$MUTANT_FLOOR" >&2
    printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
    exit 1
  fi
  printf '  ok   mutant floor: %d matrix rows went RED (floor %d)\n' "$mutants" "$MUTANT_FLOOR"
fi

# ── 5. ACCOUNTING ──────────────────────────────────────────────────────────────────
# Conservation, then the floor; both reported with printf + exit 1, never through pass()/fail().
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d) — a verdict was discarded or a call site lacks its increment.\n' \
    "$((passes + fails))" "$cases" >&2
  printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
  exit 1
fi
_floor=$ASSERT_FLOOR_BASE
[[ "$CHILD" != "1" ]] && _floor=$((ASSERT_FLOOR_BASE + ASSERT_FLOOR_MUTANTS))
if [[ "$cases" -lt "$_floor" ]]; then
  printf '\n[FATAL] assertion floor: only %d assertion(s) ran, floor is %d. Arms were deleted, skipped, or the suite exited early.\n' \
    "$cases" "$_floor" >&2
  printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
  exit 1
fi
printf '  ok   assertion floor: %d assertions ran (floor %d)\n' "$cases" "$_floor"

printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
exit $(( fails > 0 ))
