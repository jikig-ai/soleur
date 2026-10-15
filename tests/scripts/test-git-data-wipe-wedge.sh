#!/usr/bin/env bash
# Guard 7 — THE WEDGE (#10138, design-wipe-body-pr.md section 4, requirement 1; plan Phase 6).
#
# PROPERTY. After the git-data wipe deletes the plaintext volume (or only detaches it) and before
# PR-C removes `hcloud_volume.git_data` from HCL and state, no workflow other than the git-data
# dispatch's own plan-time gate (tests/scripts/lib/git-data-host-replace-gate.sh, `out_of_scope`)
# can plan a REPLACE of hcloud_server.git_data or a CREATE of hcloud_volume.git_data. The harm this
# guards is created by the wipe itself: any apply that refreshes the volume away plans a NEW volume
# id, the id flows into the rendered user_data of hcloud_server.git_data (no ignore_changes), and an
# apply nobody dispatched for that purpose replaces the live git-data host.
#
# THE POPULATION IS DERIVED, NEVER LISTED. `git ls-files .github/workflows` -> every workflow job that
# runs `terraform plan|apply` in apps/web-platform/infra (code position only: a mention inside a
# comment, an echo or a quoted string is not a command), with its -target/-replace set, the gate
# functions it sources from tests/scripts/lib, and whether it can apply at all. A new workflow cannot
# hide: it enters the population by existing.
#
# WHAT IS FED, AND WHAT DECIDES. Two synthesized plan-JSON fixtures (cq-test-fixtures-synthesized-only):
#   F1  the post-delete state: hcloud_volume.git_data CREATE beside the hcloud_server.git_data REPLACE
#       (user_data changed) and its dependents.
#   F2  the detached-not-deleted state (S3): a hcloud_volume_attachment.git_data CREATE. An unguarded
#       apply would re-attach the plaintext volume to the live host.
# Every derived job's gate(s) are fed each fixture and the verdict is printed as a matrix. A job is a
# READER of the wedge when it can plan the wedge addresses: it is untargeted, or its -target/-replace set
# (or the dependency closure of that set, read from the root's HCL) reaches one. The rule:
#   - an apply-capable READER must have a gate that REFUSES each fixture, else RED;
#   - an apply-capable non-reader is UNREACHABLE: its plan cannot contain the wedge addresses;
#   - a PLAN-ONLY reader (scheduled-terraform-drift.yml) is RECORDED, not refused: it plans, it never
#     applies, so the effect is a drift report. It is derived plan-only (no `terraform apply`, no -out).
# The sanctioned reader (the job sourcing git_data_host_replace_gate) is held harder: its gate must PASS
# the pre-wipe canonical plan, and REFUSE F1 with out_of_scope >= 1 in BOTH modes.
#
# COST (state this in the runbook and the PR body): until PR-C merges, the gates refuse every
# web-platform apply on main, security fixes included.
#
# Non-vacuity: a mutation matrix on COPIES of the workflows (and synthetic ones) proves each way to
# open the wedge goes RED for the right reason; harness rows prove an emptied fixture loader or an
# emptied derived population goes RED via a live-count floor (the floors are self-contained, they do
# not run through fail()).
#
# Run: bash tests/scripts/test-git-data-wipe-wedge.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to the repo root" >&2; exit 2; }

passes=0
fails=0
rows=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${DIR}/lib/gate-suite-harness.sh"
# shellcheck source=tests/scripts/lib/hcl-effective-text.sh
source "${DIR}/lib/hcl-effective-text.sh"
root_key_fixtures "${DIR}/lib/git-data-root-key-arm-gate.sh"
PRIOR_STATE="$(root_key_prior_state)"

INFRA_ROOT="apps/web-platform/infra"
WEDGE_ADDRS="hcloud_server.git_data,hcloud_volume.git_data,hcloud_volume_attachment.git_data"

# row <name> <ok:0|1> <detail> — the CALL-SITE counter `rows` moves independently of the verdict.
row() {
  rows=$((rows + 1))
  if [[ "$2" -eq 0 ]]; then pass; else fail "$1 — $3"; fi
}

# ── Fixtures (the same bytes as test-git-data-host-replace-gate.sh) ──────────────────────────────
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }
SERVER_REPLACE='{"address":"hcloud_server.git_data","change":{"actions":["delete","create"],"before":{"user_data":"SYNTH-OLD-USER-DATA"},"after":{"ssh_keys":["1111","4242"],"user_data":"SYNTH-NEW-USER-DATA-WITH-NEW-VOLUME-ID"},"after_unknown":{"ssh_keys":[false,false]}}}'
NET_REPLACE="$(rc_obj 'hcloud_server_network.git_data' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data' '"delete","create"')"
VA_LUKS_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data_luks' '"delete","create"')"
FW_UPDATE="$(rc_obj 'hcloud_firewall_attachment.git_data' '"update"')"
HK_SET="$(rc_obj 'tls_private_key.git_data_host_ssh' '"delete","create"'),$(rc_obj 'doppler_secret.git_data_ssh_host_key' '"update"')"
PASS_SET="${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE},${HK_SET}"

write_plan() { printf '{"prior_state":%s,"resource_changes":[%s]}' "$PRIOR_STATE" "$1" > "$2"; }

FX="${TMP}/fx"
mkdir -p "$FX"
# The pre-wipe canonical plan: the sanctioned gate must PASS it (the must-PASS control).
write_plan "${PASS_SET}" "${FX}/ctl.json"
# F1: the post-delete state. The volume is refreshed away (CREATE of a new empty store), the new id
# changes the rendered user_data, the host replaces with its dependents.
write_plan "${PASS_SET},$(rc_obj 'hcloud_volume.git_data' '"create"')" "${FX}/f1.json"
# F1 with the volume as no-op: the fixture-sensitivity row's input (the wedge content removed).
write_plan "${PASS_SET},$(rc_obj 'hcloud_volume.git_data' '"no-op"')" "${FX}/f1-noop.json"
# F2: the detached-not-deleted state: the attachment is gone, the plan would re-create it.
write_plan "$(rc_obj 'hcloud_volume_attachment.git_data' '"create"')" "${FX}/f2.json"
# An emptied fixture loader's output.
printf '{"prior_state":%s,"resource_changes":[]}' "$PRIOR_STATE" > "${FX}/empty.json"

# fixture_live <plan-file> <f1|f2|ctl> — the loader's postcondition. The wedge content must actually be
# IN the plan, or every refusal below is a refusal of nothing.
fixture_live() {
  local f="$1" kind="$2" out
  case "$kind" in
    f1) out="$(jq -r '([.resource_changes[]? | select(.address=="hcloud_volume.git_data" and .change.actions==["create"])] | length) == 1
         and ([.resource_changes[]? | select(.address=="hcloud_server.git_data" and .change.actions==["delete","create"]
             and (.change.before.user_data != .change.after.user_data))] | length) == 1' "$f" 2>/dev/null)" ;;
    f2) out="$(jq -r '[.resource_changes[]? | select(.address=="hcloud_volume_attachment.git_data" and .change.actions==["create"])] | length == 1' "$f" 2>/dev/null)" ;;
    ctl) out="$(jq -r '[.resource_changes[]? | select(.address=="hcloud_server.git_data" and .change.actions==["delete","create"])] | length == 1' "$f" 2>/dev/null)" ;;
    *) out="false" ;;
  esac
  [[ "$out" == "true" ]]
}

# ── Cleaned HCL for the dependency closure ───────────────────────────────────────────────────────
HCL="${TMP}/hcl"
mkdir -p "$HCL"
hcl_files=0
while IFS= read -r tf; do
  [[ -n "$tf" ]] || continue
  { strip_comments "$tf" | blank_heredocs; } > "${HCL}/$(basename "$tf")"
  hcl_files=$((hcl_files + 1))
done < <(git ls-files "${INFRA_ROOT}/*.tf" | grep -v "^${INFRA_ROOT}/.*/" || true)

# ── The deriver (python, stdlib + PyYAML) ───────────────────────────────────────────────────────
cat > "${TMP}/wedge_derive.py" <<'PYEOF'
import glob, json, os, re, shlex, sys

import yaml

root, hcldir, outdir, wedge_csv = sys.argv[1:5]
files = sys.argv[5:]
WEDGE = wedge_csv.split(",")
CMDRE = re.compile(r"terraform\s+(?:-chdir=(\S+)\s+)?(plan|apply)\b")
GATERE = re.compile(r"(?<![\w-])([a-z][a-z0-9_]*_gate[a-z0-9_]*)\s+(\"?[^\s;\"|]*\.json\"?)([^;\n|]*)")
SRCRE = re.compile(r"source\s+\"?\$\{GITHUB_WORKSPACE\}/(tests/scripts/lib/[\w.-]+\.sh)\"?")
CDRE = re.compile(r"(?:^|[;&\n]\s*)cd\s+[\"']?(?:\./)?" + re.escape(root) + r"[\"']?\s*(?:&&|;|\n|$)")


def scan(run):
    """terraform plan|apply invocations in CODE position -> [(kind, argstr, chdir)]"""
    i, n, stack, out = 0, len(run), ["code"], []
    while i < n:
        c, st = run[i], stack[-1]
        if st in ("code", "sub"):
            if c == "#" and (i == 0 or run[i - 1] in " \t\n;"):
                while i < n and run[i] != "\n":
                    i += 1
                continue
            if c == "'":
                stack.append("sq"); i += 1; continue
            if c == '"':
                stack.append("dq"); i += 1; continue
            if c == "\\":
                i += 2; continue
            if c == "$" and run[i + 1:i + 2] == "(":
                stack.append("sub"); i += 2; continue
            if c == "(":
                stack.append("sub"); i += 1; continue
            if c == ")" and st == "sub":
                stack.pop(); i += 1; continue
            if c == "t" and (i == 0 or run[i - 1] in " \t\n;|&($!"):
                m = CMDRE.match(run, i)
                if m:
                    j = i - 1
                    while j >= 0 and run[j] in " \t":
                        j -= 1
                    prev = run[max(0, j - 5):j + 1]
                    if j < 0 or run[j] in "\n;|&($!" or prev.endswith("--") or prev.endswith("then") \
                            or prev.endswith(" do") or prev.endswith("else"):
                        k, a, q, depth = m.end(), [], None, 0
                        while k < n:
                            ch = run[k]
                            if q is None:
                                if ch == "\\" and run[k + 1:k + 2] == "\n":
                                    a.append(" "); k += 2; continue
                                if ch == "\\":
                                    a.append(run[k:k + 2]); k += 2; continue
                                if ch in "'\"":
                                    q = ch
                                elif ch == "(":
                                    depth += 1
                                elif ch == ")":
                                    if depth == 0:
                                        break
                                    depth -= 1
                                elif ch in "\n;&|":
                                    break
                            elif ch == q and not (q == '"' and run[k - 1] == "\\"):
                                q = None
                            a.append(ch); k += 1
                        out.append((m.group(2), "".join(a), m.group(1)))
                        i = k
                        continue
            i += 1
            continue
        if st == "sq":
            if c == "'":
                stack.pop()
            i += 1; continue
        if st == "dq":
            if c == "\\":
                i += 2; continue
            if c == '"':
                stack.pop(); i += 1; continue
            if c == "$" and run[i + 1:i + 2] == "(":
                stack.append("sub"); i += 2; continue
            i += 1; continue
    return out


def toks(s):
    try:
        return shlex.split(s, posix=True)
    except ValueError:
        return s.split()


def code_lines(run):
    return "\n".join(l for l in run.split("\n") if not l.lstrip().startswith("#"))


def resolve_roots(chdir, wd, env, matrix, text, run):
    v = chdir or wd
    if v is None:
        return [root] if CDRE.search(run) else [None]
    m = re.fullmatch(r"\$\{\{\s*env\.(\w+)\s*\}\}", v)
    if m:
        return [env.get(m.group(1))]
    if re.fullmatch(r"\$\{\{\s*matrix\.directory\s*\}\}", v):
        if isinstance(matrix, list):
            return list(matrix)
        return [root] if root in text else ["?"]
    return [v]


# ---- HCL dependency graph (over the CLEANED root files) --------------------------------------
def nodes_of(texts):
    nodes = {}
    for _f, t in texts.items():
        lines, i = t.split("\n"), 0
        while i < len(lines):
            m = (re.match(r'(resource|data)\s+"([^"]+)"\s+"([^"]+)"\s*\{', lines[i])
                 or re.match(r'(module)\s+"([^"]+)"\s*\{', lines[i]) or re.match(r"(locals)\s*\{", lines[i]))
            if not m:
                i += 1; continue
            kind, d, body = m.group(1), 0, []
            while i < len(lines):
                ln = lines[i]; body.append(ln)
                s = re.sub(r'"([^"\\]|\\.)*"', '""', ln)
                d += s.count("{") - s.count("}")
                i += 1
                if d <= 0:
                    break
            if kind == "resource":
                nodes["%s.%s" % (m.group(2), m.group(3))] = body
            elif kind == "data":
                nodes["data.%s.%s" % (m.group(2), m.group(3))] = body
            elif kind == "module":
                nodes["module.%s" % m.group(2)] = body
            else:
                cur = None
                for ln in body[1:-1]:
                    mm = re.match(r"  ([A-Za-z_][\w-]*)\s*=", ln)
                    if mm:
                        cur = "local.%s" % mm.group(1); nodes.setdefault(cur, [])
                    if cur:
                        nodes[cur].append(ln)
    return nodes


def graph_of(nodes):
    names = set(nodes)
    ref = re.compile(r"(?<![\w.])((?:data\.)?[a-z][a-z0-9_]*\.[A-Za-z_][\w-]*|module\.[\w-]+|local\.[\w-]+)")
    g = {}
    for a, body in nodes.items():
        g[a] = {m.group(1) for m in ref.finditer("\n".join(body)) if m.group(1) in names and m.group(1) != a}
    return g


def closure(g, start):
    seen, st = set(), [start]
    while st:
        x = st.pop()
        for y in g.get(x, ()):
            if y not in seen:
                seen.add(y); st.append(y)
    return seen


texts = {f: open(f).read() for f in sorted(glob.glob(os.path.join(hcldir, "*.tf")))}
G = graph_of(nodes_of(texts))

records, errors, inline_n = [], [], 0
for f in files:
    try:
        text = open(f).read()
        d = yaml.safe_load(text)
    except Exception as e:  # an unparseable workflow is a finding, never a skip
        errors.append("%s: %s" % (f, type(e).__name__))
        continue
    wenv = (d or {}).get("env") or {}
    for jn, j in ((d or {}).get("jobs") or {}).items():
        env = {**wenv, **(j.get("env") or {})}
        mat = ((j.get("strategy") or {}).get("matrix") or {}).get("directory")
        jwd = ((j.get("defaults") or {}).get("run") or {}).get("working-directory")
        plans, applies, libs, calls, hit = [], [], set(), [], False
        for s in j.get("steps") or []:
            run = s.get("run")
            if not run:
                continue
            wd = s.get("working-directory", jwd)
            senv = {**env, **(s.get("env") or {})}
            for kind, a, chd in scan(run):
                if root not in resolve_roots(chd, wd, senv, mat, text, run):
                    continue
                t = toks(a)
                rec = dict(step=s.get("name"),
                           targets=[x.split("=", 1)[1] for x in t if x.startswith(("-target=", "-replace="))],
                           refresh_false="-refresh=false" in t,
                           out=any(x.startswith("-out") for x in t))
                if kind == "plan":
                    plans.append(rec)
                else:
                    rec["saved"] = any(not x.startswith("-") for x in t)
                    applies.append(rec)
                hit = True
            cl = code_lines(run)
            libs.update(SRCRE.findall(cl))
            for m in GATERE.finditer(cl):
                calls.append((m.group(1), toks(m.group(3))))
        if not hit:
            continue
        fns, network = {}, set()
        for lib in sorted(libs):
            if not os.path.isfile(lib):
                continue
            lt = open(lib).read()
            active = "\n".join(l for l in lt.split("\n") if not l.lstrip().startswith("#"))
            net = bool(re.search(r"(?m)^\s*curl\b", active))
            for fn in re.findall(r"(?m)^([a-z][a-z0-9_]*)\(\) \{", lt):
                fns[fn] = (lib, net)
        gates, seen = [], set()
        for fn, args in calls:
            if fn not in fns or (fn, tuple(args)) in seen:
                continue
            seen.add((fn, tuple(args)))
            if fns[fn][1]:
                network.add(fn)
            else:
                gates.append(dict(fn=fn, lib=fns[fn][0], args=args))
        inline = []
        if not gates:
            for s in j.get("steps") or []:
                cl = code_lines(s.get("run") or "")
                if re.search(r"terraform\s+show\s+(?:-no-color\s+)?-json\s+\S*tfplan", cl):
                    inline_n += 1
                    p = os.path.join(outdir, "inline-%d.sh" % inline_n)
                    open(p, "w").write(s["run"])
                    inline.append(dict(step=s.get("name"), file=p))
        cmds = plans + applies
        plan_only = (not applies) and not any(p["out"] for p in plans)
        untargeted = any((not p["targets"]) and not p["refresh_false"] for p in plans) \
            or any((not a["saved"]) and not a["targets"] for a in applies)
        reach = []
        if untargeted:
            reach.append("<untargeted>")
        else:
            for c in cmds:
                for tgt in c["targets"]:
                    base = re.sub(r"\[.*$", "", tgt)
                    if not base or "$" in base:
                        reach.append("<dynamic:%s>" % tgt); continue
                    if base not in G:
                        continue  # not declared in the root: -target on it plans nothing
                    for w in WEDGE:
                        if base == w or w in closure(G, base):
                            reach.append("%s->%s" % (base, w))
        records.append(dict(
            wf=f, job=jn, plan_only=plan_only, untargeted=untargeted,
            targets=sorted({x for c in cmds for x in c["targets"]}),
            reach=sorted(set(reach)), gates=gates, network_gates=sorted(network), inline=inline))

json.dump(dict(records=records, errors=errors), sys.stdout)
PYEOF

# derive_population <list-file> <out-json> — the population, from a list of workflow paths.
derive_population() {
  local list="$1" out="$2" files=()
  assert_fixture_dir "$out"
  mkdir -p "${TMP}/inline"
  mapfile -t files < "$list"
  python3 -I "${TMP}/wedge_derive.py" "$INFRA_ROOT" "$HCL" "${TMP}/inline" "$WEDGE_ADDRS" "${files[@]}" > "$out" 2>"${out}.err" || return 1
}

# The population source for the real run. git ls-files, never a hand list.
tracked_workflows() { git ls-files .github/workflows | grep -E '\.ya?ml$' || true; }

# ── Feeding a gate ───────────────────────────────────────────────────────────────────────────────
GC="${TMP}/gc"
mkdir -p "$GC"

# arg_value <token> — a synthesized value for a gate's extra argument (the gates grade the plan; the
# arguments pin the dispatch's own identifiers, which a fixture has no stake in).
arg_value() {
  local t="${1//[\$\{\}\"]/}"
  case "$t" in
    WEB_HOST_KEY) echo "web-2" ;;
    *) echo "1234" ;;
  esac
}

# gate_once <lib> <fn> <fixture> <args…> — run the REAL gate, cached by content. Sets GO_RC, GO_OUT.
GO_RC=""
GO_OUT=""
gate_once() {
  local lib="$1" fn="$2" fx="$3"; shift 3
  local key rc=0 out
  key="$(cat "$lib" "${DIR}/lib/plan-gate-preamble.sh" "$fx" <(printf '%s\n' "$fn" "$@") | sha256sum | cut -c1-40)"
  if [[ ! -f "${GC}/${key}.rc" ]]; then
    # shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
    # shellcheck source=/dev/null
    out="$( ( source "${DIR}/lib/plan-gate-preamble.sh"; source "$lib"
              if ! declare -F "$fn" >/dev/null 2>&1; then echo "GATE-UNDEFINED"; exit 127; fi
              "$fn" "$fx" "$@" 2>&1 ) )" || rc=$?
    printf '%s' "$out" > "${GC}/${key}.out"
    echo "$rc" > "${GC}/${key}.rc"
  fi
  GO_RC="$(cat "${GC}/${key}.rc")"
  GO_OUT="$(cat "${GC}/${key}.out")"
}

# gate_verdict <gate-json> <fixture> — sets GV to REFUSED (every mode variant refused) | PASSED (at least
# one variant passed) | ERROR, and GV_OUT to the gates' whole output across variants.
GV=""
GV_OUT=""
gate_verdict() {
  local g="$1" fx="$2" lib fn a modes mode args
  lib="$(jq -r '.lib' <<<"$g")"; fn="$(jq -r '.fn' <<<"$g")"
  GV="REFUSED"; GV_OUT=""
  modes="$(jq -r 'if any(.args[]?; test("GATE_MODE")) then "replace rotate" else "-" end' <<<"$g")"
  for mode in $modes; do
    args=()
    while IFS= read -r a; do
      [[ -n "$a" ]] || continue
      if [[ "$a" == *GATE_MODE* ]]; then args+=("$mode"); else args+=("$(arg_value "$a")"); fi
    done < <(jq -r '.args[]?' <<<"$g")
    gate_once "$lib" "$fn" "$fx" "${args[@]}"
    GV_OUT="${GV_OUT}${GO_OUT}"$'\n'
    if [[ "$GO_RC" == "127" || "$GO_RC" == "126" ]]; then GV="ERROR"; return 0; fi
    if [[ "$GO_RC" == "0" ]]; then GV="PASSED"; fi
  done
  return 0
}

# A shim PATH so an inline gate step runs its REAL bytes without Terraform, Doppler or a network.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
cat > "${SHIM}/terraform" <<'SHIMEOF'
#!/usr/bin/env bash
# `terraform show -json <plan>` yields the fixture; every other subcommand is a quiet success.
if [[ "${1:-}" == "show" ]]; then
  for a in "$@"; do [[ "$a" == "-json" ]] && { cat "$WEDGE_FIXTURE"; exit 0; }; done
  echo "Plan: 1 to add, 0 to change, 0 to destroy."
fi
exit 0
SHIMEOF
cat > "${SHIM}/doppler" <<'SHIMEOF'
#!/usr/bin/env bash
# `doppler run … -- <cmd…>` runs <cmd…>; anything else is a quiet success.
if [[ "${1:-}" == "run" ]]; then
  shift
  while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
  shift
  exec "$@"
fi
exit 0
SHIMEOF
chmod +x "${SHIM}/terraform" "${SHIM}/doppler"

# inline_once <script> <fixture> <head-msg> — run the step text; prints its exit status. Cached.
inline_once() {
  local script="$1" fx="$2" msg="$3" key rc w
  key="$(cat "$script" "$fx" <(printf '%s' "$msg") | sha256sum | cut -c1-40)"
  if [[ -f "${GC}/i-${key}" ]]; then cat "${GC}/i-${key}"; return 0; fi
  w="${TMP}/iw-${key}"
  mkdir -p "${w}/rt"
  printf 'Plan: 1 to add\n' > "${w}/tfplan.txt"
  rc=0
  ( cd "$w" && WEDGE_FIXTURE="$fx" PATH="${SHIM}:${PATH}" GITHUB_WORKSPACE="$REPO_ROOT" RUNNER_TEMP="${w}/rt" \
      HEAD_MSG="$msg" CI_SSH_PUB="synth" DOPPLER_TOKEN="synth" bash -c "set -eo pipefail; $(cat "$script")" >"${w}/out" 2>&1 ) || rc=$?
  echo "$rc" > "${GC}/i-${key}"
  cat "${GC}/i-${key}"
}

# ── The check ────────────────────────────────────────────────────────────────────────────────────
# wedge_run <label> <workflow-list-file> <f1> <f2> <ctl> [verbose]
#   Derives the population from the list, feeds every job's gates each fixture, applies the rules.
#   Sets WR_VIOL (count) and WR_LINES (the violation lines, one per line) and, when verbose, prints
#   the matrix. A run that cannot be graded is a violation, never a skip.
WR_VIOL=0
WR_LINES=""
WR_APPLY=0
WR_FED=0
WR_PLANONLY_READERS=0
WR_SANCTIONED=0
viol() { WR_VIOL=$((WR_VIOL + 1)); WR_LINES="${WR_LINES}$1"$'\n'; }

# Floors on the LIVE derived population (measured 2026-10-14: 15 apply-capable jobs, 2 plan-only,
# 28 gate executions). Floors, not equalities: the number grows as jobs are added.
MIN_APPLY_JOBS=12
MIN_GATE_FEEDS=20

wedge_run() {
  local label="$1" list="$2" f1="$3" f2="$4" ctl="$5" verbose="${6:-0}"
  local pop="${TMP}/pop-${label//[^A-Za-z0-9]/_}.json" rec fx fxn refused any_gate
  local wf job plan_only reach_n sanctioned n_inline ictl iv gj out_line e n_oos
  WR_VIOL=0; WR_LINES=""; WR_APPLY=0; WR_FED=0; WR_PLANONLY_READERS=0; WR_SANCTIONED=0

  # fixture loader postcondition: the wedge content must be IN the fixtures
  fixture_live "$f1" f1 || viol "FIXTURE: F1 does not carry hcloud_volume.git_data CREATE + hcloud_server.git_data REPLACE (user_data changed) — the loader returned a plan without the wedge"
  fixture_live "$f2" f2 || viol "FIXTURE: F2 does not carry the hcloud_volume_attachment.git_data CREATE — the loader returned a plan without the wedge"
  fixture_live "$ctl" ctl || viol "FIXTURE: the pre-wipe canonical plan does not carry the hcloud_server.git_data replace — the loader returned an empty control"

  if ! derive_population "$list" "$pop"; then
    viol "DERIVE: the workflow population could not be derived ($(head -c 200 "${pop}.err" 2>/dev/null))"
    return 0
  fi
  while IFS= read -r e; do
    if [[ -n "$e" ]]; then viol "DERIVE: unparseable workflow $e"; fi
  done < <(jq -r '.errors[]?' "$pop")

  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    wf="$(jq -r '.wf' <<<"$rec" | sed 's|.*/||')"; job="$(jq -r '.job' <<<"$rec")"
    plan_only="$(jq -r '.plan_only' <<<"$rec")"
    reach_n="$(jq -r '.reach | length' <<<"$rec")"
    n_inline="$(jq -r '.inline | length' <<<"$rec")"

    if [[ "$plan_only" == "true" ]]; then
      if [[ "$reach_n" -gt 0 ]]; then
        WR_PLANONLY_READERS=$((WR_PLANONLY_READERS + 1))
        if [[ "$verbose" == 1 ]]; then printf '  %-34s %-26s PLAN-ONLY READER  reach=%s (recorded: it plans, it never applies)\n' "$wf" "$job" "$(jq -r '.reach|join(",")' <<<"$rec")"; fi
      elif [[ "$verbose" == 1 ]]; then
        printf '  %-34s %-26s plan-only, cannot see the wedge (refresh disabled)\n' "$wf" "$job"
      fi
      continue
    fi
    WR_APPLY=$((WR_APPLY + 1))

    # the inline gate of a job with no sourced gate: usable only if it PASSES an empty plan (a control)
    ictl=""
    if [[ "$n_inline" -gt 0 ]]; then
      ictl="$(jq -r '.inline[0].file' <<<"$rec")"
      if [[ "$(inline_once "$ictl" "${FX}/empty.json" "")" != "0" ]]; then ictl=""; fi
    fi

    out_line=""
    for fxn in f1 f2; do
      if [[ "$fxn" == f1 ]]; then fx="$f1"; else fx="$f2"; fi
      refused=0; any_gate=0
      while IFS= read -r gj; do
        [[ -n "$gj" ]] || continue
        any_gate=$((any_gate + 1))
        gate_verdict "$gj" "$fx"
        WR_FED=$((WR_FED + 1))
        case "$GV" in
          REFUSED) refused=1 ;;
          ERROR) viol "GATE-ERROR: ${wf}::${job} gate $(jq -r '.fn' <<<"$gj") could not run on ${fxn} (undefined or unrunnable) — an ungradable gate is not a refusal" ;;
        esac
      done < <(jq -c '.gates[]?' <<<"$rec")
      if [[ -n "$ictl" ]]; then
        any_gate=$((any_gate + 1)); WR_FED=$((WR_FED + 1))
        iv="$(inline_once "$ictl" "$fx" "")"
        # the unacked run: the unackable HALTs (a host create) are what bind here
        if [[ "$iv" != "0" ]]; then refused=1; fi
      fi
      if [[ "$refused" -eq 1 ]]; then out_line="${out_line} ${fxn}=REFUSED"; else out_line="${out_line} ${fxn}=PASSES"; fi
      if [[ "$reach_n" -gt 0 && "$refused" -eq 0 ]]; then
        viol "WEDGE-OPEN: ${wf}::${job} can plan the wedge (reach: $(jq -r '.reach|join(", ")' <<<"$rec" | cut -c1-200)) and no gate of it refuses ${fxn} (gates fed: ${any_gate})"
      fi
    done
    if [[ "$verbose" == 1 ]]; then
      if [[ "$reach_n" -gt 0 ]]; then
        printf '  %-34s %-26s%s  [READER, gated]\n' "$wf" "$job" "$out_line"
      else
        printf '  %-34s %-26s%s  [unreachable: -target set + dependency closure exclude the wedge]\n' "$wf" "$job" "$out_line"
      fi
    fi

    # the sanctioned reader: its own gate is held to the stronger statement
    sanctioned="$(jq -c '.gates[]? | select(.fn=="git_data_host_replace_gate")' <<<"$rec" | head -n 1)"
    if [[ -n "$sanctioned" ]]; then
      WR_SANCTIONED=$((WR_SANCTIONED + 1))
      gate_once "${DIR}/lib/git-data-host-replace-gate.sh" git_data_host_replace_gate "$ctl" replace
      if [[ "$GO_RC" != "0" ]]; then
        viol "SANCTIONED: ${wf}::${job} git_data_host_replace_gate does not PASS the pre-wipe canonical plan (replace) — the refusal of F1 would prove nothing"
      fi
      gate_verdict "$sanctioned" "$f1"
      n_oos="$(grep -Ec 'out_of_scope=[1-9]' <<<"$GV_OUT" || true)"
      if [[ "$GV" != "REFUSED" ]]; then
        viol "SANCTIONED: ${wf}::${job} git_data_host_replace_gate does not REFUSE F1 (the post-delete state) in both modes (${GV})"
      elif [[ "$n_oos" -lt 2 ]]; then
        viol "SANCTIONED: ${wf}::${job} git_data_host_replace_gate refused F1 but not through out_of_scope in both modes (the hcloud_volume.git_data create)"
      fi
    fi
  done < <(jq -c '.records[]' "$pop")

  if [[ "$WR_SANCTIONED" -lt 1 ]]; then viol "SANCTIONED: no derived job sources git_data_host_replace_gate — the sanctioned reader is absent from the population"; fi
  if [[ "$WR_APPLY" -lt "$MIN_APPLY_JOBS" ]]; then viol "FLOOR: only ${WR_APPLY} apply-capable jobs derived, floor ${MIN_APPLY_JOBS} — the population is empty or truncated"; fi
  if [[ "$WR_FED" -lt "$MIN_GATE_FEEDS" ]]; then viol "FLOOR: only ${WR_FED} gate executions, floor ${MIN_GATE_FEEDS} — gates were not fed"; fi
  return 0
}

# ── 1. The real population, the real fixtures ────────────────────────────────────────────────────
tracked_workflows > "${TMP}/real.list"
echo "== Guard 7: the wedge — derived population fed F1 (post-delete) and F2 (detached) =="
wedge_run real "${TMP}/real.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json" 1
real_viol="$WR_VIOL"
real_lines="$WR_LINES"
real_apply="$WR_APPLY"
real_fed="$WR_FED"
real_sanctioned="$WR_SANCTIONED"
real_readers="$WR_PLANONLY_READERS"
printf '  apply-capable jobs: %s, gate executions: %s, sanctioned gates: %s, plan-only readers: %s\n' "$real_apply" "$real_fed" "$real_sanctioned" "$real_readers"
printf '  not fed (probe the Hetzner API, not plan-content gates): %s\n' "$(jq -r '[.records[].network_gates[]] | unique | join(", ")' "${TMP}/pop-real.json")"
row "W1 the wedge is closed: no derived path can plan it and pass" "$((real_viol == 0 ? 0 : 1))" "$(printf '%s' "$real_lines" | head -c 1500)"
row "W2 the second reader is recorded: at least one plan-only workflow reads the wedge (drift)" "$((real_readers >= 1 ? 0 : 1))" "no plan-only reader derived — the runbook's second-reader sentence has no subject"
tracked_n="$(tracked_workflows | wc -l)"
row "W3 the population source is git ls-files (all tracked workflows, a live count)" "$([[ "$tracked_n" -ge 40 && "$tracked_n" -eq "$(wc -l < "${TMP}/real.list")" ]] && echo 0 || echo 1)" "tracked=${tracked_n}, listed=$(wc -l < "${TMP}/real.list")"
row "W4 the real fixtures carry the wedge (loader postcondition)" "$(fixture_live "${FX}/f1.json" f1 && fixture_live "${FX}/f2.json" f2 && fixture_live "${FX}/ctl.json" ctl && echo 0 || echo 1)" "a fixture lost its wedge content"

# ── 2. Mutation matrix (Guard 7) on COPIES of the workflows ─────────────────────────────────────
WFM="${TMP}/wfm"
mkdir -p "$WFM"
APPLY_WF=".github/workflows/apply-web-platform-infra.yml"
DRIFT_WF=".github/workflows/scheduled-terraform-drift.yml"

# mutate_list <out-list> <mutated-path:original-path…> — the population list with the named files
# replaced by their mutated copies.
mutate_list() {
  local out="$1"; shift
  local p pair sub
  assert_fixture_dir "$out"
  : > "$out"
  while IFS= read -r p; do
    sub=""
    for pair in "$@"; do
      if [[ "${pair#*:}" == "$p" ]]; then sub="${pair%%:*}"; fi
    done
    if [[ -n "$sub" ]]; then echo "$sub" >> "$out"; else echo "$p" >> "$out"; fi
  done < <(tracked_workflows)
}

# expect_red <name> <needle> — the last wedge_run must have produced a violation containing <needle>.
expect_red() {
  local name="$1" needle="$2"
  if [[ -n "${WEDGE_DEBUG:-}" ]]; then printf '  [debug] %s\n%s' "$name" "$(printf '%s' "$WR_LINES" | cut -c1-240)" >&2; fi
  if [[ "$WR_VIOL" -gt 0 && "$WR_LINES" == *"$needle"* ]]; then
    row "$name" 0 ""
  else
    row "$name" 1 "wanted RED with '${needle}', got ${WR_VIOL} violation(s): $(printf '%s' "$WR_LINES" | head -c 400)"
  fi
}

# M1 add hcloud_volume_attachment.git_data to the per-merge apply's -target set. The per-merge guard
# (inline destroy-guard counters) refuses F1's server REPLACE but passes F2: only the target set kept
# the attachment out of that plan.
awk '{ print } /^ *-target=betteruptime_policy\.github_webhook \\$/ && !d { match($0, /^ */); printf "%s-target=hcloud_volume_attachment.git_data \\\n", substr($0, 1, RLENGTH); d=1 }' "$APPLY_WF" > "${WFM}/m1.yml"
if cmp -s "${WFM}/m1.yml" "$APPLY_WF"; then row "M1 (mutation matched)" 1 "the per-merge plan anchor drifted; the mutation changed nothing"; else
  mutate_list "${TMP}/m1.list" "${WFM}/m1.yml:${APPLY_WF}"
  wedge_run m1 "${TMP}/m1.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
  expect_red "M1 wedge address added to the per-merge apply's -target set -> RED" "WEDGE-OPEN: m1.yml::apply"
fi

# M1b the closure arm: a target that DEPENDS on the git-data host (doppler_secret.git_transport_ssh_private_key
# has depends_on = [hcloud_server.git_data]) pulls it into the plan though the address is never written.
awk '{ print } /^ *-target=betteruptime_policy\.github_webhook \\$/ && !d { match($0, /^ */); printf "%s-target=doppler_secret.git_transport_ssh_private_key \\\n", substr($0, 1, RLENGTH); d=1 }' "$APPLY_WF" > "${WFM}/m1b.yml"
if cmp -s "${WFM}/m1b.yml" "$APPLY_WF"; then row "M1b (mutation matched)" 1 "the per-merge plan anchor drifted; the mutation changed nothing"; else
  mutate_list "${TMP}/m1b.list" "${WFM}/m1b.yml:${APPLY_WF}"
  wedge_run m1b "${TMP}/m1b.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
  expect_red "M1b a target whose DEPENDENCY CLOSURE reaches the git-data host -> RED" "->hcloud_server.git_data"
fi

# M1c the wedge host added to a job with no gate that can be fed (the ci_ssh token replace).
awk '/Terraform plan \(ci_ssh token replace/ { f=1 } f && /^ *-replace=/ && !d { match($0, /^ */); printf "%s-target=hcloud_server.git_data \\\n", substr($0, 1, RLENGTH); d=1 } { print }' "$APPLY_WF" > "${WFM}/m1c.yml"
if cmp -s "${WFM}/m1c.yml" "$APPLY_WF"; then row "M1c (mutation matched)" 1 "the ci_ssh plan anchor drifted; the mutation changed nothing"; else
  mutate_list "${TMP}/m1c.list" "${WFM}/m1c.yml:${APPLY_WF}"
  wedge_run m1c "${TMP}/m1c.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
  expect_red "M1c hcloud_server.git_data added to an ungated job's -target set -> RED" "WEDGE-OPEN: m1c.yml::ci_ssh_token_replace"
fi

# M2 an untargeted apply path: a new workflow that applies the root with no -target.
cat > "${WFM}/m2.yml" <<'WFEOF'
name: synthetic untargeted apply
on: workflow_dispatch
jobs:
  apply_everything:
    runs-on: ubuntu-24.04
    steps:
      - name: Terraform apply
        working-directory: apps/web-platform/infra
        run: |
          set -euo pipefail
          terraform apply -auto-approve -input=false
WFEOF
{ cat "${TMP}/real.list"; echo "${WFM}/m2.yml"; } > "${TMP}/m2.list"
wedge_run m2 "${TMP}/m2.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
expect_red "M2 an untargeted apply path -> RED" "WEDGE-OPEN: m2.yml::apply_everything"

# M3 a second such workflow after a compliant first: a targeted unrelated apply, then an untargeted one.
cat > "${WFM}/m3a.yml" <<'WFEOF'
name: synthetic compliant apply
on: workflow_dispatch
jobs:
  apply_one_record:
    runs-on: ubuntu-24.04
    steps:
      - name: Terraform apply
        working-directory: apps/web-platform/infra
        run: |
          terraform apply -auto-approve -input=false -target=cloudflare_record.app
WFEOF
{ cat "${TMP}/real.list"; echo "${WFM}/m3a.yml"; echo "${WFM}/m2.yml"; } > "${TMP}/m3.list"
wedge_run m3 "${TMP}/m3.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
if [[ "$WR_LINES" == *"m3a.yml"* ]]; then row "M3 (control) the compliant first workflow stays quiet" 1 "the compliant workflow was flagged: $(printf '%s' "$WR_LINES" | head -c 300)"; else row "M3 (control) the compliant first workflow stays quiet" 0 ""; fi
expect_red "M3 a second, untargeted workflow after a compliant first -> RED" "WEDGE-OPEN: m2.yml::apply_everything"

# M4 fixture sensitivity: F1 with the volume as no-op. The sanctioned gate then PASSES it, so the
# statement "the gate refuses F1 through out_of_scope" is carried by the volume CREATE alone.
wedge_run m4 "${TMP}/real.list" "${FX}/f1-noop.json" "${FX}/f2.json" "${FX}/ctl.json"
expect_red "M4 F1 with hcloud_volume.git_data as no-op instead of create -> RED (fixture sensitivity: the sanctioned gate then PASSES F1)" "does not REFUSE F1"

# M5 the derived population emptied.
: > "${TMP}/m5.list"
wedge_run m5 "${TMP}/m5.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
expect_red "M5 an emptied derived population -> RED via the live-count floor" "FLOOR: only 0 apply-capable"
# M5b the population truncated to workflows that cannot carry the apply paths.
git ls-files .github/workflows | grep -v -E 'apply-web-platform-infra|apply-deploy-pipeline-fix' | head -n 5 > "${TMP}/m5b.list"
wedge_run m5b "${TMP}/m5b.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
expect_red "M5b a population truncated to unrelated workflows -> RED via the floor" "FLOOR"

# M6 the plan-only reader gains an apply: drift stops being a recorded reader and becomes an
# untargeted apply path.
awk '{ print } /echo "exit_code=\$EXIT_CODE" >> "\$GITHUB_OUTPUT"/ && !d { match($0, /^ */); printf "%sterraform apply -auto-approve -input=false\n", substr($0, 1, RLENGTH); d=1 }' "$DRIFT_WF" > "${WFM}/m6.yml"
if cmp -s "${WFM}/m6.yml" "$DRIFT_WF"; then row "M6 (mutation matched)" 1 "the drift anchor drifted; the mutation changed nothing"; else
  mutate_list "${TMP}/m6.list" "${WFM}/m6.yml:${DRIFT_WF}"
  wedge_run m6 "${TMP}/m6.list" "${FX}/f1.json" "${FX}/f2.json" "${FX}/ctl.json"
  expect_red "M6 the plan-only drift workflow gains an apply -> RED" "WEDGE-OPEN: m6.yml::drift-check"
fi

# ── 3. Harness rows ─────────────────────────────────────────────────────────────────────────────
# H1 a suite edit that makes the fixture loader return an EMPTY plan must go RED (the refusals would
# otherwise be refusals of nothing: every gate refuses an empty plan).
wedge_run h1 "${TMP}/real.list" "${FX}/empty.json" "${FX}/empty.json" "${FX}/empty.json"
expect_red "H1 an emptied fixture loader -> RED (fixture liveness)" "FIXTURE"
# H2 must-PASS: the pre-wipe canonical plan passes the sanctioned gate (the control that keeps every
# refusal above attributable to the wedge content).
gate_once "${DIR}/lib/git-data-host-replace-gate.sh" git_data_host_replace_gate "${FX}/ctl.json" replace
row "H2 the pre-wipe canonical plan PASSES the sanctioned gate (replace)" "$([[ "$GO_RC" == "0" ]] && echo 0 || echo 1)" "the control fixture no longer passes — the PASS_SET constructors drifted from test-git-data-host-replace-gate.sh"
# H3 the loader postcondition rejects an empty plan.
row "H3 the loader postcondition rejects an empty plan" "$(fixture_live "${FX}/empty.json" f1 && echo 1 || echo 0)" "fixture_live accepted an empty plan"
# H4 the derivation is not vacuous: the real population contains the per-merge apply job.
row "H4 the derived population includes the per-merge apply job" "$(jq -e '[.records[] | select(.wf|endswith("apply-web-platform-infra.yml")) | select(.job=="apply")] | length == 1' "${TMP}/pop-real.json" >/dev/null 2>&1 && echo 0 || echo 1)" "the per-merge apply job is not in the derived population"
row "H5 the closure reads the HCL (cleaned files present)" "$((hcl_files >= 30 ? 0 : 1))" "only ${hcl_files} cleaned .tf files"

# ── Anti-vacuity floors (self-contained: bash builtins and this suite's own counters) ─────────────
# `rows` is incremented at the CALL SITE of row(), independently of the verdict, so a fail() stub cannot
# hide a failure behind a healthy count; conservation ties it to the tally.
_ran=$((passes + fails))
if [[ "$_ran" -lt 19 || "$rows" -ne "$_ran" ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: %s verdicts for %s rows (floor 19, and the two must agree). Rows were deleted, skipped, or the suite exited early.\n' "$_ran" "$rows"
else
  printf '  ok   anti-vacuity floor: %s rows ran (floor 19)\n' "$_ran"
fi
_pop="$real_apply"
if [[ "$_pop" -lt 12 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: %s apply-capable jobs derived, floor 12. The population is empty or truncated.\n' "$_pop"
else
  printf '  ok   population floor: %s apply-capable jobs derived (floor 12)\n' "$_pop"
fi

echo ""
echo "=== test-git-data-wipe-wedge.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
