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
#     applies only an additive plan (a create of exactly the D-1 address set, or a no-op; no
#     import, no moved address, no re-mint of an anchored key; NO rotation exception), gates the
#     apply on that refusal (no `if:` / `continue-on-error` from the allowlist through the apply),
#     prints the fingerprint from Terraform state only when it equals the Hetzner object's, never
#     prints or uploads the plan, shreds it, and emails ops on any non-success.
#   - apply-web-platform-infra.yml's push trigger excludes the root, and infra-validation.yml runs
#     this suite and validates the root.
#
# THE STEP BODIES ARE EXECUTED, NOT RE-DECLARED. The `validate`, `allowlist` and `fingerprint` step
# bodies are extracted from the workflow by step id (PyYAML) and run under `bash -e` with PATH-stubbed
# `terraform`/`doppler`/`curl` that serve synthesized plan-JSON, state-JSON and Hetzner-listing
# fixtures (cq-test-fixtures-synthesized-only: every value below is a fabricated placeholder or an
# ED25519 key generated into the scratch dir at test time, never a real key or token).
#
# MUTATION BATTERY (harness convention, modeled on arm-heartbeats.test.sh). Every code-edit row
# copies the file under test, applies a sed edit to the copy, asserts the edit landed on exactly the
# expected deleted/added line counts, points an override at the copy (GD_ROOT_KEY_DIR,
# GD_ROOT_KEY_WORKFLOW, GD_ROOT_KEY_APPLY_WF, GD_ROOT_KEY_PARENT_DIR) and re-runs this suite as a
# child, requiring the NAMED case to print FAIL. Fixture rows run as negative cases. Every row is
# DECLARED when it starts and COUNTED only on a RED verdict; the floor requires red == declared.
#
#   row  guard  kind     edit / fixture                                              must go RED
#   F1   G8     fixture  tls_private_key.git_data_root actions ["forget"]            G8.fixture-forget
#   F2   G8     fixture  read-token replace (no rotation exception)                  G8.fixture-token-replace
#   F3   G8     fixture  empty `terraform show -json` output                         G8.fixture-empty-json
#   F4   G8     fixture  create of an address outside the D-1 set                    G8.fixture-unexpected-create
#   F5   G8     fixture  a D-1 create that is an import                              G8.fixture-importing
#   F6   G8     fixture  a no-op carrying previous_address (moved)                   G8.fixture-moved
#   F7   G8     fixture  tls key create with the fingerprint committed               G8.remint-refused
#   F8   G8     fixture  state fingerprint differs from the Hetzner object's         G8.fingerprint-mismatch
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
#   M15  G8     code     continue-on-error: true on the allowlist step                G8.allowlist-gates-apply
#   M16  G8     code     if: always() on the apply step                               G8.allowlist-gates-apply
#   M17  G8     code     notify job if: gains a trailing `&& false`                   G8.notify-job
#   M18  G8     code     mail step if: always() -> if: false                          G8.notify-job
#   M19  G8     code     drop hcloud_ssh_key.git_data_root from create_addrs          G8.create-set-parity
#   M20  G8     code     re-point the allowlist's fingerprint-anchor path             G8.remint-refused
#   M21  G8     code     drop the importing check from `additive`                     G8.fixture-importing
#   M22  G8     code     fingerprint step reads the saved plan, not state             G8.fingerprint-match
#   M23  G8     code     neuter the state-vs-Hetzner equality                         G8.fingerprint-mismatch
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

MUTANT_FLOOR=31

passes=0
fails=0
skips=0
cases=0
mutants=0   # rows that produced a RED verdict
declared=0  # rows started (fixture rows + code rows); the floor requires mutants == declared
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
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null && command -v jq >/dev/null 2>&1 \
     && command -v ssh-keygen >/dev/null 2>&1; then
  pass "PRE.tools: python3 + PyYAML + jq + ssh-keygen available"
else
  fail "PRE.tools: python3 with PyYAML, jq and ssh-keygen are required — the arms below cannot run and must not read as green"
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
rp = block(t, r'^\s*required_providers\s*\{') or ""
sources = sorted(set(s.lower() for s in re.findall(r'source\s*=\s*"([^"]+)"', rp)))
print("REQUIRED_SOURCES=%s" % ",".join(sources))
print("LOCK_NAMES=%s" % ",".join(sorted(ml)))
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
# Parity, not literals: a provider bump lands in the parent's lock and must land here in the same PR.
_lock_names="$(fact "$ROOT_FACTS" LOCK_NAMES)"
if [[ -n "$_lock_names" && "$_lock_names" == "$(fact "$ROOT_FACTS" REQUIRED_SOURCES)" \
      && -z "$(fact "$ROOT_FACTS" LOCK_PARENT_MISMATCH)" ]]; then
  pass "ROOT.lock: the lock pins exactly the required_providers sources, each at the parent lock's version"
else
  fail "ROOT.lock: locked providers drifted from required_providers or from the parent's lock" \
    "lock=${_lock_names} required=$(fact "$ROOT_FACTS" REQUIRED_SOURCES) parent-mismatch=$(fact "$ROOT_FACTS" LOCK_PARENT_MISMATCH)"
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
    "replace_flag": code.count("-replace"),
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
print("CONFIRM_ENV=%d" % (1 if venv == {"CONFIRM_RAW": "${{ inputs.confirm }}"}
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
    m = re.search(r"def create_addrs:\s*\[(.*?)\];", prog, re.S)
    print("CREATE_SET=%s" % (",".join(sorted(re.findall(r'"([^"]+)"', m.group(1)))) if m else ""))
    ai = [i for i, s in enumerate(steps) if s is al][0]
    ap = [i for i, s in enumerate(steps) if re.search(r"terraform apply\b", str(s.get("run", "")))]
    print("ALLOWLIST_BEFORE_APPLY=%d" % (1 if ap and all(ai < i for i in ap) else 0))
    # THE WIRING, not the content: a refusal that does not stop the apply is an annotation. No step
    # from the allowlist through the one apply may carry `if:` (always()/false both bypass the
    # default success() gate), and neither end may carry continue-on-error; nor may the job.
    gate = (len(ap) == 1 and ai < ap[0]
            and all("if" not in steps[i] for i in range(ai, ap[0] + 1))
            and "continue-on-error" not in al and "continue-on-error" not in steps[ap[0]]
            and "continue-on-error" not in apply)
    print("ALLOWLIST_GATE=%d" % (1 if gate else 0))
fp = next((s for s in steps if s.get("id") == "fingerprint"), None)
if fp:
    body = str(fp.get("run", ""))
    open(os.path.join(work, "fingerprint.sh"), "w").write(body)
    shows = re.findall(r"terraform show\b[^\n]*", body)
    m = re.search(r"terraform show -json \| jq -r '([^']*)'", body)
    fields = sorted(set(re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", re.sub(r'"(?:[^"\\]|\\.)*"', '""', m.group(1))))) if m else []
    print("FP_SOURCE=%d|%s|%s" % (len(shows), 1 if m else 0, ",".join(fields)))
    print("FP_WD=%s" % resolve(fp.get("working-directory", "")))

notify = jobs.get("notify-root-key-apply") or {}
needs = notify.get("needs") or []
needs = [needs] if isinstance(needs, str) else needs
ifx = str(notify.get("if", ""))
nsteps = notify.get("steps") or []
mail = [s for s in nsteps if s.get("uses") == "./.github/actions/notify-ops-email"
        and (s.get("with") or {}).get("resend-api-key") == "${{ secrets.RESEND_API_KEY }}"]
# EXACT compares: a substring check accepts `... && false`; a mail step `if: false` (or a
# continue-on-error on it) silences the notice while the job still "runs".
mail_ok = len(mail) == 1 and all(("if" not in m or str(m.get("if")).strip() == "always()")
                                 and "continue-on-error" not in m for m in mail)
print("NOTIFY=%d|%d|%d|%d|%d" % (1 if notify else 0, 1 if "apply" in needs else 0,
      1 if ifx.strip() == "always() && needs.apply.result != 'success'" else 0,
      1 if "environment" not in notify else 0, 1 if mail_ok else 0))

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
if [[ "$(fact "$WF_FACTS" INPUTS)" == "confirm" ]]; then
  pass "WF.inputs: exactly {confirm} (no rotation input; a rotation is a reviewed PR adding a typed arm)"
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
if [[ "$(fact "$WF_FACTS" BANS)" == "TF_LOG:0,replace_flag:0,run_inputs_interp:0,terraform_output:0,upload-artifact:0" ]]; then
  pass "G8.census: no upload-artifact, terraform output, TF_LOG, -replace, or \${{ inputs. }} inside a run body"
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
  pass "WF.confirm: the validate step runs first and receives exactly the confirm input through env:"
else
  fail "WF.confirm: input validation is not first or its env: is not exactly {CONFIRM_RAW: inputs.confirm}" \
    "first=$(fact "$WF_FACTS" VALIDATE_FIRST) env=$(fact "$WF_FACTS" CONFIRM_ENV)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" JQ_FIELDS)" == "actions,address,change,importing,previous_address,resource_changes" ]]; then
  pass "G8.jq-fields: the allowlist program reads only resource_changes[] address, change.actions, change.importing, previous_address"
else
  fail "G8.jq-fields: the allowlist program reads fields beyond address/actions/importing/previous_address" "fields=$(fact "$WF_FACTS" JQ_FIELDS)"
fi

# The workflow keeps a LITERAL create set (it cannot parse HCL at run time); the set it must equal is
# derived from the root's *.tf, so adding or dropping a resource without the allowlist fails here.
cases=$((cases + 1))
_create_set="$(fact "$WF_FACTS" CREATE_SET)"
if [[ -n "$_create_set" && "$_create_set" == "$(fact "$ROOT_FACTS" ADDRS)" ]]; then
  pass "G8.create-set-parity: the allowlist's create_addrs literal equals the root's declared address set"
else
  fail "G8.create-set-parity: create_addrs differs from the addresses declared in the root's *.tf" \
    "allowlist=${_create_set:-<none extracted>} root=$(fact "$ROOT_FACTS" ADDRS)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" ALLOWLIST_GATE)" == "1" ]]; then
  pass "G8.allowlist-gates-apply: no if:/continue-on-error from the allowlist step through the one apply (nor on the job)"
else
  fail "G8.allowlist-gates-apply: the allowlist refusal no longer gates the apply" \
    "gate=$(fact "$WF_FACTS" ALLOWLIST_GATE) — an if: or continue-on-error lets a refused plan apply"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" FP_SOURCE)" == "1|1|address,public_key_fingerprint_sha256,resources,root_module,values" \
      && "$(fact "$WF_FACTS" FP_WD)" == "apps/web-platform/infra/git-data-root-key" ]]; then
  pass "G8.fingerprint-state-source: one terraform show -json (no plan file) piped into jq reading only the tls key's public_key_fingerprint_sha256, in the root dir"
else
  fail "G8.fingerprint-state-source: the fingerprint step's state read drifted (shows|state-form|fields)" \
    "$(fact "$WF_FACTS" FP_SOURCE) wd=$(fact "$WF_FACTS" FP_WD)"
fi

cases=$((cases + 1))
if [[ "$(fact "$WF_FACTS" NOTIFY)" == "1|1|1|1|1" ]]; then
  pass "G8.notify-job: notify-root-key-apply needs apply, if: is exactly always() && result != success, no environment, one ungated notify-ops-email step"
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
# Synthesized-fixture stub. `terraform show -json <saved plan>` serves $FIXTURE; `terraform show
# -json` with NO operand (state) serves $STATE_FIXTURE. Anything else is an unexpected invocation.
if [[ "${1:-}" == "show" && "${2:-}" == "-json" ]]; then
  if [[ $# -eq 3 && "$3" == "${RUNNER_TEMP:-}/tfplan" ]]; then
    [[ "${STUB_SHOW_RC:-0}" -eq 0 ]] || exit "$STUB_SHOW_RC"
    cat "$FIXTURE"
    exit 0
  fi
  if [[ $# -eq 2 && -n "${STATE_FIXTURE:-}" ]]; then
    [[ "${STUB_STATE_RC:-0}" -eq 0 ]] || exit "$STUB_STATE_RC"
    cat "$STATE_FIXTURE"
    exit 0
  fi
fi
echo "terraform stub: unexpected invocation: $*" >&2
exit 64
SH
cat > "$STUB/doppler" <<'SH'
#!/usr/bin/env bash
# Synthesized-fixture stub: `doppler secrets get HCLOUD_TOKEN ... --plain` prints $HC_TOKEN.
if [[ "${1:-} ${2:-} ${3:-}" == "secrets get HCLOUD_TOKEN" ]]; then
  [[ "${STUB_DOPPLER_RC:-0}" -eq 0 ]] || exit "$STUB_DOPPLER_RC"
  printf '%s' "$HC_TOKEN"
  exit 0
fi
echo "doppler stub: unexpected invocation" >&2
exit 64
SH
cat > "$STUB/curl" <<'SH'
#!/usr/bin/env bash
# Synthesized-fixture stub: drains the header from stdin, serves $HETZNER_FIXTURE for the
# label-selected ssh_keys listing only.
cat >/dev/null
case " $* " in
  *" https://api.hetzner.cloud/v1/ssh_keys?label_selector=soleur-role%3Dgit-data-root "*) ;;
  *) echo "curl stub: unexpected URL" >&2; exit 64 ;;
esac
[[ "${STUB_CURL_RC:-0}" -eq 0 ]] || exit "$STUB_CURL_RC"
cat "$HETZNER_FIXTURE"
SH
chmod +x "$STUB/terraform" "$STUB/doppler" "$STUB/curl"

# Fingerprint-anchor workspaces: one with the committed fingerprint file, one without.
WS_NONE="$WORK/ws-none"
WS_ANCHORED="$WORK/ws-anchored"
mkdir -p "$WS_NONE" "$WS_ANCHORED/apps/web-platform/infra"
printf 'SHA256:SYNTHETIC-placeholder-not-a-fingerprint\n' > "$WS_ANCHORED/apps/web-platform/infra/git-data-root-key.fingerprint"

run_validate() {  # <confirm> -> sets V_RC V_OUT
  V_OUT="$(cd "$WORK" && env CONFIRM_RAW="$1" bash -e "$WORK/validate.sh" 2>&1)"
  V_RC=$?
}

run_allowlist() {  # <fixture-file> <workspace: none|anchored|unset> [show-rc] -> sets A_RC A_OUT
  local ws
  case "$2" in
    anchored) ws="$WS_ANCHORED" ;;
    unset)    ws="" ;;
    *)        ws="$WS_NONE" ;;
  esac
  A_OUT="$(cd "$WORK" && env PATH="$STUB:$PATH" FIXTURE="$1" GITHUB_WORKSPACE="$ws" STUB_SHOW_RC="${3:-0}" \
             RUNNER_TEMP="$WORK" bash -e "$WORK/allowlist.sh" 2>&1)"
  A_RC=$?
}

SENT="SYNTHETIC-SENTINEL-not-a-key-0000"
TOKEN_SENT="SYNTHETIC-TOKEN-not-a-token-1111"
fixture() {  # <name> <json-resource_changes-array> -> path
  local p="$WORK/fx-$1.json"
  printf '{"format_version":"1.2","variables":{"hcloud_token":{"value":"%s"}},"resource_changes":%s,"prior_state":{"values":{"root_module":{"resources":[{"values":{"private_key_openssh":"%s"}}]}}}}\n' \
    "$SENT" "$2" "$SENT" > "$p"
  printf '%s' "$p"
}
rc_entry() {  # <address> <actions-json> [extra top-level json members] [extra change json members]
  printf '{"address":"%s","mode":"managed"%s,"change":{"actions":%s,"after":{"value":"%s"}%s}}' \
    "$1" "${3:+,$3}" "$2" "$SENT" "${4:+,$4}"
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

if [[ ! -s "$WORK/validate.sh" || ! -s "$WORK/allowlist.sh" || ! -s "$WORK/fingerprint.sh" ]]; then
  cases=$((cases + 1)); fail "G8.extract: could not extract the validate/allowlist/fingerprint step bodies by id"
else
  cases=$((cases + 1)); pass "G8.extract: validate, allowlist and fingerprint step bodies extracted by step id"
fi

# validate step
run_validate "APPLY-GIT-DATA-ROOT-KEY"
cases=$((cases + 1))
[[ "$V_RC" -eq 0 ]] && pass "WF.validate-accepts: exact confirm -> rc 0" \
  || fail "WF.validate-accepts: exact confirm rejected (rc=$V_RC)" "$V_OUT"
for _bad in "apply-git-data-root-key" "APPLY-GIT-DATA-ROOT-KEY " "" "REHEARSE-GIT-DATA"; do
  run_validate "$_bad"
  cases=$((cases + 1))
  [[ "$V_RC" -ne 0 ]] && pass "WF.validate-rejects-confirm: '${_bad}' -> refused" \
    || fail "WF.validate-rejects-confirm: '${_bad}' accepted as confirm"
done

# allowlist step
_ok() {  # <case-id> <desc> <fixture> <workspace>
  run_allowlist "$3" "$4"
  cases=$((cases + 1))
  if [[ "$A_RC" -eq 0 && "${A_OUT%%$'\n'*}" == "verdict=ok" && "$A_OUT" != *"$SENT"* ]]; then
    pass "$1: $2 -> verdict=ok"
  else
    fail "$1: $2 -> expected verdict=ok (rc=$A_RC)" "$(printf '%s' "$A_OUT" | head -3)"
  fi
}
_refused() {  # <case-id> <desc> <fixture> <workspace> <verdict> [expected-line] [matrix-row] [show-rc]
  [[ "${7:-}" == "row" ]] && declared=$((declared + 1))
  run_allowlist "$3" "$4" "${8:-0}"
  cases=$((cases + 1))
  if [[ "$A_RC" -ne 0 && "$A_OUT" == *"verdict=$5"* && ( -z "${6:-}" || "$A_OUT" == *"$6"* ) && "$A_OUT" != *"$SENT"* ]]; then
    pass "$1: $2 -> refused verdict=$5"
    [[ "${7:-}" == "row" ]] && mutants=$((mutants + 1))
  else
    fail "$1: $2 -> expected refusal verdict=$5 (rc=$A_RC)" "$(printf '%s' "$A_OUT" | head -3)"
  fi
}

FX_CREATE="$(fixture create "$(all7 '["create"]')")"
: > "$WORK/fx-empty.json"

# VERDICT-HELPER SELF-TEST, both directions. Drive _ok and _refused once with a known-GREEN and once
# with a known-RED input, require each to record exactly the verdict it was handed (and _refused to
# declare its matrix row either way but count it only when the refusal was observed), then roll
# every counter back.
# Reported via printf + exit, never through the helpers under test.
_st_p=$passes; _st_f=$fails; _st_c=$cases; _st_m=$mutants; _st_d=$declared
_st_bad=""
_ok "SELFTEST.ok-green" "all create" "$FX_CREATE" none >/dev/null
[[ "$passes" -eq $((_st_p + 1)) && "$fails" -eq "$_st_f" ]] || _st_bad="${_st_bad} ok-green"
_ok "SELFTEST.ok-red" "empty plan" "$WORK/fx-empty.json" none >/dev/null
[[ "$passes" -eq $((_st_p + 1)) && "$fails" -eq $((_st_f + 1)) ]] || _st_bad="${_st_bad} ok-red"
_refused "SELFTEST.refused-green" "empty plan" "$WORK/fx-empty.json" none git_data_root_key_plan_unreadable "" row >/dev/null
[[ "$passes" -eq $((_st_p + 2)) && "$fails" -eq $((_st_f + 1)) && "$mutants" -eq $((_st_m + 1)) && "$declared" -eq $((_st_d + 1)) ]] \
  || _st_bad="${_st_bad} refused-green"
_refused "SELFTEST.refused-red" "all create" "$FX_CREATE" none git_data_root_key_non_additive "" row >/dev/null
[[ "$passes" -eq $((_st_p + 2)) && "$fails" -eq $((_st_f + 2)) && "$mutants" -eq $((_st_m + 1)) && "$declared" -eq $((_st_d + 2)) ]] \
  || _st_bad="${_st_bad} refused-red"
[[ "$cases" -eq $((_st_c + 4)) ]] || _st_bad="${_st_bad} cases"
if [[ -n "$_st_bad" ]]; then
  printf '\n[FATAL] verdict-helper self-test: _ok/_refused mis-recorded:%s (passes %d->%d, fails %d->%d, mutants %d->%d, declared %d->%d).\n' \
    "$_st_bad" "$_st_p" "$passes" "$_st_f" "$fails" "$_st_m" "$mutants" "$_st_d" "$declared" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f; cases=$_st_c; mutants=$_st_m; declared=$_st_d

_ok "G8.allow-create-only" "all seven D-1 addresses create, no fingerprint committed" "$FX_CREATE" none
_ok "G8.allow-noop" "no-op everywhere" "$(fixture noop "$(all7 '["no-op"]')")" none
_ok "G8.anchor-scoped" "fingerprint committed, only the Hetzner object is re-created" \
  "$(fixture hkeycre "$(all7 '["no-op"]' hcloud_ssh_key.git_data_root '["create"]')")" anchored
_ok "G8.importing-null" "explicit importing:null on a create is not an import" \
  "$(fixture impnull "[$(rc_entry tls_private_key.git_data_root '["create"]' "" '"importing":null')]")" none

_refused "G8.fixture-forget" "tls_private_key.git_data_root forget" \
  "$(fixture forget "$(all7 '["no-op"]' tls_private_key.git_data_root '["forget"]')")" none \
  git_data_root_key_non_additive "refused tls_private_key.git_data_root forget" row
_refused "G8.fixture-token-replace" "read-token replace (no rotation exception)" \
  "$(fixture tokrepl "$(all7 '["no-op"]' doppler_service_token.git_data_root_read '["delete","create"]' github_actions_secret.doppler_token_git_data_root '["update"]')")" none \
  git_data_root_key_non_additive "refused doppler_service_token.git_data_root_read delete,create" row
_refused "G8.fixture-empty-json" "empty show -json output" "$WORK/fx-empty.json" none \
  git_data_root_key_plan_unreadable "" row
_refused "G8.fixture-unexpected-create" "create of an address outside the D-1 set" \
  "$(fixture rogue "[$(rc_entry hcloud_ssh_key.rogue '["create"]'),$(rc_entry tls_private_key.git_data_root '["no-op"]')]")" none \
  git_data_root_key_non_additive "refused hcloud_ssh_key.rogue create" row
_refused "G8.fixture-importing" "a D-1 create that is an import" \
  "$(fixture importing "[$(rc_entry hcloud_ssh_key.git_data_root '["create"]' "" '"importing":{"id":"000000"}')]")" none \
  git_data_root_key_non_additive "refused hcloud_ssh_key.git_data_root create importing" row
_refused "G8.fixture-moved" "a no-op carrying previous_address" \
  "$(fixture moved "[$(rc_entry doppler_project.git_data_root '["no-op"]' '"previous_address":"doppler_project.old"')]")" none \
  git_data_root_key_non_additive "refused doppler_project.git_data_root no-op moved" row
_refused "G8.remint-refused" "tls key create with the fingerprint committed" "$FX_CREATE" anchored \
  git_data_root_key_remint_refused "refused tls_private_key.git_data_root create" row
_refused "G8.anchor-unset-workspace" "GITHUB_WORKSPACE unset" "$FX_CREATE" unset git_data_root_key_anchor_unreadable
_refused "G8.fixture-read" "a read action (the root declares no data source)" \
  "$(fixture read "$(all7 '["no-op"]' tls_private_key.git_data_root '["read"]')")" none \
  git_data_root_key_non_additive "refused tls_private_key.git_data_root read"
_refused "G8.fixture-delete" "hcloud_ssh_key.git_data_root delete" \
  "$(fixture del "$(all7 '["no-op"]' hcloud_ssh_key.git_data_root '["delete"]')")" none git_data_root_key_non_additive \
  "refused hcloud_ssh_key.git_data_root delete"
_refused "G8.fixture-update" "doppler_secret update" \
  "$(fixture upd "$(all7 '["no-op"]' doppler_secret.git_data_root_ssh_private_key '["update"]')")" none \
  git_data_root_key_non_additive "refused doppler_secret.git_data_root_ssh_private_key update"
_refused "G8.fixture-replace" "tls key create-before-destroy replace" \
  "$(fixture repl "$(all7 '["no-op"]' tls_private_key.git_data_root '["create","delete"]')")" none \
  git_data_root_key_non_additive "refused tls_private_key.git_data_root create,delete"
printf '{"resource_changes": [' > "$WORK/fx-invalid.json"
_refused "G8.fixture-invalid-json" "truncated JSON" "$WORK/fx-invalid.json" none git_data_root_key_plan_unreadable
printf '{"format_version":"1.2"}\n' > "$WORK/fx-nochanges.json"
_refused "G8.fixture-no-resource-changes" "no resource_changes key" "$WORK/fx-nochanges.json" none git_data_root_key_plan_unreadable
_refused "G8.fixture-empty-resource-changes" "resource_changes: []" "$(fixture emptyrc '[]')" none git_data_root_key_plan_unreadable
_refused "G8.fixture-actions-not-array" "actions as a bare string" \
  "$(fixture strAct '[{"address":"tls_private_key.git_data_root","change":{"actions":"create"}}]')" none git_data_root_key_plan_unreadable
_refused "G8.fixture-show-fails" "terraform show exits non-zero" "$FX_CREATE" none git_data_root_key_plan_unreadable "" "" 1

# fingerprint step. Two ED25519 keys generated into the scratch dir (synthesized, never committed).
ssh-keygen -q -t ed25519 -N '' -C synthetic-a -f "$WORK/key-a" >/dev/null 2>&1
ssh-keygen -q -t ed25519 -N '' -C synthetic-b -f "$WORK/key-b" >/dev/null 2>&1
FP_A="$(ssh-keygen -l -E sha256 -f "$WORK/key-a.pub" 2>/dev/null | awk '{print $2}')"
FP_B="$(ssh-keygen -l -E sha256 -f "$WORK/key-b.pub" 2>/dev/null | awk '{print $2}')"
cases=$((cases + 1))
if [[ "$FP_A" =~ ^SHA256:[A-Za-z0-9+/]{43}$ && "$FP_B" =~ ^SHA256:[A-Za-z0-9+/]{43}$ && "$FP_A" != "$FP_B" ]]; then
  pass "G8.fingerprint-keys: two distinct synthesized ED25519 keys generated"
else
  fail "G8.fingerprint-keys: could not generate synthesized keys" "a=${FP_A} b=${FP_B}"
fi
state_fixture() {  # <name> <tls-fingerprint> -> path. A decoy fingerprint on another address proves the select.
  local p="$WORK/st-$1.json"
  printf '{"format_version":"1.0","values":{"root_module":{"resources":[{"address":"hcloud_ssh_key.git_data_root","values":{"public_key_fingerprint_sha256":"%s"}},{"address":"tls_private_key.git_data_root","values":{"private_key_openssh":"%s","public_key_fingerprint_sha256":"%s"}}]}}}\n' \
    "$FP_B" "$SENT" "$2" > "$p"
  printf '%s' "$p"
}
hetzner_fixture() {  # <name> <key-count> <name-field> -> path; every listed key carries key-a's public half
  local p="$WORK/hz-$1.json" pub keys="" i
  pub="$(cut -d' ' -f1-2 "$WORK/key-a.pub")"
  for ((i = 0; i < $2; i++)); do
    keys="${keys:+$keys,}$(printf '{"id":%d,"name":"%s","fingerprint":"aa:bb:cc","public_key":"%s"}' "$i" "$3" "$pub")"
  done
  printf '{"ssh_keys":[%s]}\n' "$keys" > "$p"
  printf '%s' "$p"
}
run_fingerprint() {  # <state-fixture> <hetzner-fixture> [state-rc] [curl-rc] -> sets F_RC F_OUT F_SUMMARY
  : > "$WORK/step-summary.md"
  F_OUT="$(cd "$WORK" && env PATH="$STUB:$PATH" STATE_FIXTURE="$1" HETZNER_FIXTURE="$2" FIXTURE="$FX_CREATE" \
             STUB_STATE_RC="${3:-0}" STUB_CURL_RC="${4:-0}" HC_TOKEN="$TOKEN_SENT" RUNNER_TEMP="$WORK" \
             GITHUB_STEP_SUMMARY="$WORK/step-summary.md" bash -e "$WORK/fingerprint.sh" 2>&1)"
  F_RC=$?
  F_SUMMARY="$(cat "$WORK/step-summary.md")"
}
# Nothing but the fingerprint prints: no private-key sentinel, and the token only on its add-mask line.
fp_clean() { [[ "$F_OUT" != *"$SENT"* && "$F_SUMMARY" != *"$SENT"* ]] && [[ "$(grep -v '^::add-mask::' <<<"$F_OUT" | grep -cF -- "$TOKEN_SENT" || true)" == 0 ]]; }

HZ_ONE="$(hetzner_fixture one 1 soleur-git-data-root)"
run_fingerprint "$(state_fixture a "$FP_A")" "$HZ_ONE"
cases=$((cases + 1))
if [[ "$F_RC" -eq 0 ]] && grep -qxF "git_data_root_key_fingerprint=${FP_A}" <<<"$F_OUT" \
     && [[ "$F_SUMMARY" == *"\`${FP_A}\`"* ]] && fp_clean; then
  pass "G8.fingerprint-match: state fingerprint == Hetzner-derived -> prints the state fingerprint only"
else
  fail "G8.fingerprint-match: expected rc 0 printing the state fingerprint (rc=$F_RC)" "$(grep -v '^::add-mask::' <<<"$F_OUT" | head -3)"
fi

_fp_refused() {  # <case-id> <desc> <verdict-and-reason> [matrix-row] -- uses F_RC/F_OUT already set
  cases=$((cases + 1))
  if [[ "$F_RC" -ne 0 && "$F_OUT" == *"::error::verdict=$3"* && "$F_OUT" != *"git_data_root_key_fingerprint=SHA256"* ]] && fp_clean; then
    pass "$1: $2 -> refused verdict=$3"
    [[ "${4:-}" == "row" ]] && mutants=$((mutants + 1))
  else
    fail "$1: $2 -> expected refusal verdict=$3 (rc=$F_RC)" "$(grep -v '^::add-mask::' <<<"$F_OUT" | head -3)"
  fi
}

# _fp_refused self-test, both directions, same contract as the allowlist helpers' above.
_st_p=$passes; _st_f=$fails; _st_c=$cases; _st_m=$mutants
F_RC=1; F_OUT="::error::verdict=selftest_word"; F_SUMMARY=""
_fp_refused "SELFTEST.fp-refused-green" "synthetic refusal" selftest_word row >/dev/null
[[ "$passes" -eq $((_st_p + 1)) && "$fails" -eq "$_st_f" && "$mutants" -eq $((_st_m + 1)) ]] || _st_bad="${_st_bad} fp-refused-green"
F_RC=0; F_OUT="git_data_root_key_fingerprint=SHA256:selftest"
_fp_refused "SELFTEST.fp-refused-red" "synthetic success" selftest_word row >/dev/null
[[ "$passes" -eq $((_st_p + 1)) && "$fails" -eq $((_st_f + 1)) && "$mutants" -eq $((_st_m + 1)) && "$cases" -eq $((_st_c + 2)) ]] \
  || _st_bad="${_st_bad} fp-refused-red"
if [[ -n "$_st_bad" ]]; then
  printf '\n[FATAL] verdict-helper self-test: _fp_refused mis-recorded:%s (passes %d->%d, fails %d->%d, mutants %d->%d).\n' \
    "$_st_bad" "$_st_p" "$passes" "$_st_f" "$fails" "$_st_m" "$mutants" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f; cases=$_st_c; mutants=$_st_m

declared=$((declared + 1))
run_fingerprint "$(state_fixture b "$FP_B")" "$HZ_ONE"
_fp_refused "G8.fingerprint-mismatch" "state holds key-b, Hetzner lists key-a" git_data_root_key_fingerprint_mismatch row
cases=$((cases + 1))
if [[ "$F_OUT" != *"$FP_A"* && "$F_OUT" != *"$FP_B"* && -z "$F_SUMMARY" ]]; then
  pass "G8.fingerprint-mismatch-silent: a mismatch prints neither fingerprint and writes no summary"
else
  fail "G8.fingerprint-mismatch-silent: a mismatch leaked a fingerprint to the log or the step summary"
fi
run_fingerprint "$(state_fixture a "$FP_A")" "$HZ_ONE" 1
_fp_refused "G8.fingerprint-state-unreadable" "terraform show (state) exits non-zero" \
  "git_data_root_key_fingerprint_unreadable reason=state_read_failed"
run_fingerprint "$(state_fixture absent "")" "$HZ_ONE"
_fp_refused "G8.fingerprint-state-absent" "no fingerprint on the tls key in state" \
  "git_data_root_key_fingerprint_unreadable reason=state_fingerprint_malformed"
run_fingerprint "$(state_fixture a "$FP_A")" "$HZ_ONE" 0 22
_fp_refused "G8.fingerprint-hetzner-list-failed" "the Hetzner listing call fails" \
  "git_data_root_key_fingerprint_unreadable reason=hetzner_list_failed"
run_fingerprint "$(state_fixture a "$FP_A")" "$(hetzner_fixture two 2 soleur-git-data-root)"
_fp_refused "G8.fingerprint-hetzner-count" "two keys under the label" \
  "git_data_root_key_fingerprint_unreadable reason=hetzner_key_count"
run_fingerprint "$(state_fixture a "$FP_A")" "$(hetzner_fixture forged 1 soleur-git-data-rooT)"
_fp_refused "G8.fingerprint-hetzner-name" "one key under the label with the wrong name" \
  "git_data_root_key_fingerprint_unreadable reason=hetzner_key_name"

# ── 4. MUTATION BATTERY (parent run only) ──────────────────────────────────────────
MUTANT=""
mutate() {  # <name> <src-file> <want del/add> <sed-expr> [dir-kind: root|parent] -> sets MUTANT (file or dir)
  local name="$1" src="$2" want="$3" expr="$4" kind="${5:-}"
  local dst target del add
  declared=$((declared + 1))
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
  if mutate jq-forget "$WF" "1/1" 's/(\.\[1\] == \["no-op"\] or expected_create)/(.[1] == ["no-op"] or .[1] == ["forget"] or expected_create)/'; then
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

  # M15 continue-on-error on the allowlist: the refusal would annotate and the apply would still run
  if mutate allowlist-coe "$WF" "0/1" 's/^        id: allowlist$/&\n        continue-on-error: true/'; then
    expect_red allowlist-coe G8.allowlist-gates-apply GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M16 if: always() on the apply: runs after a refused allowlist
  if mutate apply-always "$WF" "0/1" 's/^      - name: Terraform apply (saved plan)$/&\n        if: always()/'; then
    expect_red apply-always G8.allowlist-gates-apply GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M17 notify job if: keeps both substrings but never fires
  if mutate notify-if-suffix "$WF" "1/1" "s/^    if: always() && needs.apply.result != 'success'\$/& \&\& false/"; then
    expect_red notify-if-suffix G8.notify-job GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M18 mail step if: false
  if mutate mail-if-false "$WF" "1/1" '/^      - name: Email ops on a non-green root-key apply$/,/uses:/ s/^        if: always()$/        if: false/'; then
    expect_red mail-if-false G8.notify-job GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M19 drop one address from the allowlist's create set
  if mutate create-set-drop "$WF" "1/0" '/^            "hcloud_ssh_key.git_data_root",$/d'; then
    expect_red create-set-drop G8.create-set-parity GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M20 re-point the fingerprint-anchor path: the re-mint refusal never arms
  if mutate anchor-path "$WF" "1/1" 's|/apps/web-platform/infra/git-data-root-key.fingerprint" \]\]; then anchored=true|/apps/web-platform/infra/git-data-root-key.fingerprints" ]]; then anchored=true|'; then
    expect_red anchor-path G8.remint-refused GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M21 drop the importing check
  if mutate importing-dropped "$WF" "1/1" 's/def additive: \.\[2\] == null and /def additive: /'; then
    expect_red importing-dropped G8.fixture-importing GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M22 the fingerprint step reads the saved plan instead of state
  if mutate fp-reads-plan "$WF" "1/1" 's/state_fp="\$(terraform show -json | jq -r /state_fp="$(terraform show -json "$RUNNER_TEMP\/tfplan" | jq -r /'; then
    expect_red fp-reads-plan G8.fingerprint-match GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi
  # M23 neuter the state-vs-Hetzner equality
  if mutate fp-equality "$WF" "1/1" 's/^          if \[\[ "\$state_fp" != "\$hetzner_fp" \]\]; then$/          if false; then/'; then
    expect_red fp-equality G8.fingerprint-mismatch GD_ROOT_KEY_WORKFLOW="$MUTANT"
  fi

  # MUTANT FLOOR, reported directly. Every DECLARED row (fixture rows + code rows) must have produced
  # a RED verdict — a row whose edit did not land, or whose child stayed green, is declared but not
  # counted — and the declared set must not shrink below the matrix above.
  if [[ "$mutants" -ne "$declared" || "$mutants" -lt "$MUTANT_FLOOR" ]]; then
    printf '\n[FATAL] mutant floor: %d of %d declared matrix rows went RED (floor %d).\n' "$mutants" "$declared" "$MUTANT_FLOOR" >&2
    printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
    exit 1
  fi
  printf '  ok   mutant floor: %d of %d declared matrix rows went RED (floor %d)\n' "$mutants" "$declared" "$MUTANT_FLOOR"
fi

# ── 5. ACCOUNTING ──────────────────────────────────────────────────────────────────
# Conservation, then the floor; both reported with printf + exit 1, never through pass()/fail().
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d) — a verdict was discarded or a call site lacks its increment.\n' \
    "$((passes + fails))" "$cases" >&2
  printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
  exit 1
fi
ASSERT_FLOOR_BASE=87
ASSERT_FLOOR_MUTANTS=48
_floor=$((ASSERT_FLOOR_BASE + ASSERT_FLOOR_MUTANTS * (${CHILD:-0} != 1)))
if [[ "$cases" -lt "$_floor" ]]; then
  printf '\n[FATAL] assertion floor: only %d assertion(s) ran, floor is %d. Arms were deleted, skipped, or the suite exited early.\n' \
    "$cases" "$_floor" >&2
  printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
  exit 1
fi
printf '  ok   assertion floor: %d assertions ran (floor %d)\n' "$cases" "$_floor"

printf '\n=== git-data-root-key: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$skips"
exit $(( fails > 0 ))
