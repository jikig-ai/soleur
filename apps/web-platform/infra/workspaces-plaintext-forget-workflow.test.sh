#!/usr/bin/env bash
#
# Structural + behavioral gate for .github/workflows/workspaces-plaintext-forget.yml (#6604 runbook
# step 7, Guard 4) — the single-use workflow that `terraform state rm`s web-1's two retired plaintext
# workspaces addresses once the volume is measured gone. Deleted in PR B together with the workflow.
#
# THE PROPERTY: an address is forgotten only when the pinned volume is gone from Hetzner (proven with a
# token that can SEE the project), the state instance's id equals the pin, and nothing else is removed.
# And no byte of this root's state — which holds random_password.workspaces_luks — reaches a log, a
# file or an artifact.
#
# Structural rows parse the YAML (a grep would match the prose). Behavioral rows EXECUTE the extracted
# `gone` and `forget` step bodies under GitHub's own `bash --noprofile --norc -eo pipefail`, against a
# curl stub (prints what -w '%{http_code}' prints; exits 22 under -f on a 404, like the real one), a gh
# stub, and a terraform stub that mutates a synthesized state file the way `state rm` does.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO/.github/workflows/workspaces-plaintext-forget.yml"
APPLY_WF="$REPO/.github/workflows/apply-web-platform-infra.yml"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
# Instrument self-test (the sibling suites' harness_selftest, inlined: this suite has no harness).
_st="$( pass=0; fail=0; ok x >/dev/null; no y >/dev/null; printf '%s/%s' "$pass" "$fail" )"
[[ "$_st" == "1/1" ]] || { printf 'INSTRUMENT FAIL - ok()/no() self-test got %s, want 1/1\n' "$_st"; exit 2; }

[[ -f "$WF" ]] || { no "the forget workflow is missing at $WF"; printf '\n%s passed, %s failed\n' "$pass" "$fail"; exit 1; }
python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

SCRATCH="$(mktemp -d -t wl-forget.XXXXXXXX)" || { printf 'INSTRUMENT FAIL - mktemp\n'; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- structural, parsed as YAML ----------------------------------------------------------------
python3 - "$WF" "$APPLY_WF" "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PY'
import sys, re, yaml
wf_path, apply_path, scratch = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(wf_path).read()
wf = yaml.safe_load(text)
ap = yaml.safe_load(open(apply_path))
out = []
def check(name, cond, detail=""):
    d = str(detail)[:200].replace("\t", " ").replace("\n", " ")
    out.append(("ok" if cond else "FAIL", name, d))

on = wf.get(True) or wf.get("on") or {}
inp = ((on.get("workflow_dispatch") or {}).get("inputs")) or {}
check("dispatch-only (workflow_dispatch is the only trigger)", set(on) == {"workflow_dispatch"}, sorted(on))
check("inputs are exactly confirm + expected_plaintext_volume_id", set(inp) == {"confirm", "expected_plaintext_volume_id"}, sorted(inp))
conc = wf.get("concurrency") or {}
apply_group = (ap.get("concurrency") or {}).get("group")
check("workflow-level concurrency group is the apply workflows' literal (the SOLE serializer of the lockless state)",
      conc.get("group") == apply_group == "terraform-apply-web-platform-host", f"{conc.get('group')} vs {apply_group}")
check("cancel-in-progress is false", conc.get("cancel-in-progress") is False)
check("permissions are exactly contents:read + actions:read", wf.get("permissions") == {"contents": "read", "actions": "read"}, wf.get("permissions"))
env = wf.get("env") or {}
check("TERRAFORM_VERSION equals apply-web-platform-infra.yml's", env.get("TERRAFORM_VERSION") == (ap.get("env") or {}).get("TERRAFORM_VERSION"),
      f"{env.get('TERRAFORM_VERSION')} vs {(ap.get('env') or {}).get('TERRAFORM_VERSION')}")
check("the pin is a CONSTANT in the file (PINNED=105149570)", str(env.get("PINNED")) == "105149570", env.get("PINNED"))
jobs = wf.get("jobs") or {}
check("exactly one job, `forget`", list(jobs) == ["forget"], list(jobs))
job = jobs.get("forget") or {}
check("the job's environment is infra-privileged (Tier-B, main-only, no reviewer)", job.get("environment") == "infra-privileged", repr(job.get("environment")))
steps = job.get("steps") or []
def idx(pred):
    for i, st in enumerate(steps):
        if pred(st):
            return i
    return -1
i_val = idx(lambda st: st.get("id") == "validate")
i_loader = idx(lambda st: st.get("uses") == "./.github/actions/infra-credentials")
i_extract = idx(lambda st: st.get("name") == "Extract backend credentials")
i_init = idx(lambda st: st.get("name") == "Terraform init")
i_gone = idx(lambda st: st.get("id") == "gone")
i_forget = idx(lambda st: st.get("id") == "forget")
check("step order: validate < loader < extract < init < gone < forget",
      -1 not in (i_val, i_loader, i_extract, i_init, i_gone, i_forget) and i_val < i_loader < i_extract < i_init < i_gone < i_forget,
      (i_val, i_loader, i_extract, i_init, i_gone, i_forget))
runs = [st for st in steps if st.get("run")]
check("every run: step refuses to run under xtrace", all(re.search(r"case \$- in \*x\*\)", str(st["run"])) for st in runs),
      [st.get("name") for st in runs if not re.search(r"case \$- in \*x\*\)", str(st["run"]))])
check("no run: body interpolates ${{ inputs.* }} (inputs reach shell only via env:)", not any("${{ inputs." in str(st["run"]) for st in runs))
# The extract/init steps are the apply job's own, copied verbatim (plus the xtrace prelude).
apply_steps = ((ap.get("jobs") or {}).get("apply") or {}).get("steps") or []
a_ex = next((st for st in apply_steps if st.get("name") == "Extract backend credentials"), None)
if i_extract >= 0 and a_ex:
    mine = re.sub(r"^case \$- in \*x\*\).*\n", "", str(steps[i_extract].get("run", "")))
    check("Extract backend credentials is the apply job's step verbatim (after the xtrace prelude)",
          mine.strip() == str(a_ex.get("run", "")).strip() and steps[i_extract].get("env") == a_ex.get("env"))
if i_init >= 0:
    st = steps[i_init]
    check("Terraform init runs -input=false -lockfile=readonly in the main root",
          "terraform init -input=false -lockfile=readonly" in str(st.get("run", "")) and st.get("working-directory") == "${{ env.INFRA_DIR }}"
          and env.get("INFRA_DIR") == "apps/web-platform/infra")
body = "\n".join(str(st.get("run", "")) for st in steps)
code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
pulls = [l for l in code.splitlines() if "terraform state pull" in l]
check("terraform state pull appears, and ONLY piped straight into jq (never printed, tee'd, or redirected to a file)",
      len(pulls) >= 1 and all(re.search(r"terraform state pull \| jq -c \"\$IDENT_JQ\"\s*;?\s*\}?\s*$", l) for l in pulls), pulls)
check("no artifact upload and no tee anywhere in the workflow", "upload-artifact" not in text and not re.search(r"\btee\b", code))
jq_prog = re.search(r"IDENT_JQ='(.*?)'", code, re.S)
jq_prog = jq_prog.group(1) if jq_prog else ""
check("the identity jq program exists", bool(jq_prog))
for t, n in (("hcloud_volume", "workspaces"), ("hcloud_volume_attachment", "workspaces"), ("hcloud_server", "web")):
    check(f"the identity filter selects {t}.{n} by EXACT .type and .name",
          f'.type == "{t}" and .name == "{n}"' in jq_prog)
check("the identity filter never selects by address prefix (workspaces_luks shares the prefix)",
      not re.search(r"startswith|test\(|contains\(|ltrimstr|\.address", jq_prog))
check("the identity filter emits no attribute other than id / volume_id (no state secret can ride it)",
      set(re.findall(r"\.attributes\.([a-z_]+)", jq_prog)) <= {"id", "volume_id"}, re.findall(r"\.attributes\.([a-z_]+)", jq_prog))
tf_verbs = re.findall(r"terraform\s+(apply|destroy|plan|import|state\s+(?:push|mv|rm|pull|list|show)|taint|untaint)", code)
check("the only terraform verbs are state pull / state list / state rm (no apply, destroy, plan, push, mv, show)",
      set(tf_verbs) <= {"state pull", "state list", "state rm"} and "state rm" in tf_verbs, sorted(set(tf_verbs)))
check("exactly ONE `terraform state rm` invocation (serial is pinned to pre + 1)", len(re.findall(r"terraform state rm ", code)) == 1)
for sid, fn in (("gone", "gone.sh"), ("forget", "forget.sh"), ("validate", "validate.sh")):
    hits = [st for st in steps if st.get("id") == sid]
    check(f"exactly one step with id {sid}", len(hits) == 1, len(hits))
    if len(hits) == 1:
        open(f"{scratch}/{fn}", "w").write(str(hits[0].get("run", "")))
for v in out:
    print("\t".join(v))
PY
while IFS=$'\t' read -r verdict name detail; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"

# --- stubs ------------------------------------------------------------------------------------------
BIN="$SCRATCH/bin"; FIX="$SCRATCH/fix"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
method=GET out="" wfmt="" url="" fail=0 cfg=0
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    -w) wfmt="$2"; shift 2 ;;
    -H|--data|--max-time) shift 2 ;;
    --config) [ "$2" = - ] && cfg=1; shift 2 ;;
    -sS|-s|-S) shift ;;
    -f|--fail|-fsS|-fs) fail=1; shift ;;
    https://*) url="$1"; shift ;;
    *) echo "STUB_UNKNOWN_FLAG curl $1" >> "$CURL_LOG"; exit 64 ;;
  esac
done
if [ "$cfg" = 1 ]; then cat >> "$CURL_CFG"; fi
path="${url#https://api.hetzner.cloud/v1}"
printf '%s %s\n' "$method" "$path" >> "$CURL_LOG"
key="$(printf '%s_%s' "$method" "$path" | tr -c 'A-Za-z0-9_\n' '_')"
n=0; [ -f "$FIX/$key.n" ] && n="$(cat "$FIX/$key.n")"; echo $((n + 1)) > "$FIX/$key.n"
i="$n"; while [ "$i" -ge 0 ] && [ ! -f "$FIX/$key.$i" ]; do i=$((i - 1)); done
if [ "$i" -lt 0 ]; then code=599; body='{}'; else code="$(head -n1 "$FIX/$key.$i")"; body="$(tail -n +2 "$FIX/$key.$i")"; fi
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
if [ "$fail" = 1 ] && [ "$code" -ge 400 ]; then exit 22; fi
[ -n "$wfmt" ] && printf '%s' "$code"
exit 0
STUB
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$*" in
  *"actions/workflows/apply-web-platform-infra.yml"*) printf '{"state":"%s"}\n' "${GH_STATE_APPLY:-disabled_manually}" ;;
  *"actions/workflows/apply-deploy-pipeline-fix.yml"*) printf '{"state":"%s"}\n' "${GH_STATE_PIPELINE:-disabled_manually}" ;;
  "run list"*"--workflow apply-web-platform-infra.yml"*) printf '%s\n' "${GH_RUNS_APPLY:-[]}" ;;
  "run list"*"--workflow apply-deploy-pipeline-fix.yml"*) printf '%s\n' "${GH_RUNS_PIPELINE:-[]}" ;;
  *) echo "STUB_UNKNOWN gh $*" >> "$GH_LOG"; exit 64 ;;
esac
STUB
# terraform: `state pull` prints the fixture, `state list` derives addresses, `state rm` removes the
# named instances and bumps serial once — or misbehaves on a knob (TF_RM_EXTRA / TF_RM_NOOP /
# TF_SERIAL_BUMP / TF_LINEAGE_CHANGE) so the post-verification has something to catch.
cat > "$BIN/terraform" <<'STUB'
#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >> "$TF_LOG"
addr_jq='.resources[] | select(.mode == "managed") | . as $r | .instances[] | "\($r.type).\($r.name)" + (if .index_key == null then "" elif (.index_key | type) == "string" then "[\"\(.index_key)\"]" else "[\(.index_key)]" end)'
case "${1:-} ${2:-}" in
  "state pull") cat "$TF_STATE" ;;
  "state list") jq -r "$addr_jq" "$TF_STATE" ;;
  "state rm")
    shift 2
    [ "${TF_RM_NOOP:-0}" = 1 ] && { echo "Removed (noop stub)"; exit 0; }
    for a in "$@"; do
      t="${a%%.*}"; rest="${a#*.}"; n="${rest%%[*}"; k="${rest#*[\"}"; k="${k%\"]}"
      jq --arg t "$t" --arg n "$n" --arg k "$k" \
        '(.resources[] | select(.type == $t and .name == $n) | .instances) |= map(select(.index_key != $k))' "$TF_STATE" > "$TF_STATE.tmp" && mv "$TF_STATE.tmp" "$TF_STATE"
      echo "Removed $a"
    done
    if [ "${TF_RM_EXTRA:-0}" = 1 ]; then
      jq '(.resources[] | select(.type == "hcloud_server" and .name == "web") | .instances) |= map(select(.index_key != "web-2"))' "$TF_STATE" > "$TF_STATE.tmp" && mv "$TF_STATE.tmp" "$TF_STATE"
    fi
    jq --argjson b "${TF_SERIAL_BUMP:-1}" '.serial += $b' "$TF_STATE" > "$TF_STATE.tmp" && mv "$TF_STATE.tmp" "$TF_STATE"
    [ "${TF_LINEAGE_CHANGE:-0}" = 1 ] && { jq '.lineage = "lin-OTHER"' "$TF_STATE" > "$TF_STATE.tmp" && mv "$TF_STATE.tmp" "$TF_STATE"; }
    echo "Successfully removed $# resource instance(s)." ;;
  *) echo "STUB_UNKNOWN terraform $*" >> "$TF_LOG"; exit 64 ;;
esac
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/sleep"
chmod +x "$BIN"/*

SECRET='SUPER-SECRET-PASSPHRASE-SYNTH-6604'
state_fixture() {  # [vol=yes|no] [att=yes|no] [server=yes|no] [vol_id] [att_vid]
  local vol="${1:-yes}" att="${2:-yes}" srv="${3:-yes}" vid="${4:-105149570}" avid="${5:-105149570}"
  jq -n --arg vol "$vol" --arg att "$att" --arg srv "$srv" --arg vid "$vid" --argjson avid "$avid" --arg secret "$SECRET" '
    {version: 4, serial: 41, lineage: "lin-1", resources: [
      {mode: "managed", type: "hcloud_server", name: "web", instances:
        ([{index_key: "web-2", attributes: {id: "167390740"}}] + (if $srv == "yes" then [{index_key: "web-1", attributes: {id: "123931471"}}] else [] end))},
      {mode: "managed", type: "hcloud_volume", name: "workspaces", instances:
        ([{index_key: "web-2", attributes: {id: "106466179"}}] + (if $vol == "yes" then [{index_key: "web-1", attributes: {id: $vid}}] else [] end))},
      {mode: "managed", type: "hcloud_volume_attachment", name: "workspaces", instances:
        ([{index_key: "web-2", attributes: {id: "106466179", volume_id: 106466179}}] + (if $att == "yes" then [{index_key: "web-1", attributes: {id: "105149570", volume_id: $avid}}] else [] end))},
      {mode: "managed", type: "hcloud_volume", name: "workspaces_luks", instances: [{attributes: {id: "106443278"}}]},
      {mode: "managed", type: "random_password", name: "workspaces_luks", instances: [{attributes: {result: $secret}}]}
    ]}' > "$SCRATCH/state.json"
}
fx_reset() { rm -rf "$FIX"; mkdir -p "$FIX"; : > "$SCRATCH/curl.log"; : > "$SCRATCH/curl.cfg"; : > "$SCRATCH/gh.log"; : > "$SCRATCH/tf.log"; }
fx() { local key; key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9_\n' '_')"; printf '%s\n%s' "$4" "$5" > "$FIX/$key.$3"; }
fx_gone() {
  fx GET "/servers/123931471" 0 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[106443278]}}'
  fx GET "/volumes/105149570" 0 404 '{"error":{"code":"not_found"}}'
  fx GET "/volumes?name=soleur-web-platform-data" 0 200 '{"volumes":[]}'
}
# run_step <file> [VAR=value ...] -> RC, OUT, and the files GitHub would read after the step
run_step() {
  local f="$1"; shift
  : > "$SCRATCH/gh_output"; : > "$SCRATCH/gh_summary"; : > "$SCRATCH/gh_env"
  RC=0
  OUT="$(cd "$SCRATCH" && env PATH="$BIN:$PATH" CURL_LOG="$SCRATCH/curl.log" CURL_CFG="$SCRATCH/curl.cfg" FIX="$FIX" \
    GH_LOG="$SCRATCH/gh.log" TF_LOG="$SCRATCH/tf.log" TF_STATE="$SCRATCH/state.json" \
    GITHUB_OUTPUT="$SCRATCH/gh_output" GITHUB_STEP_SUMMARY="$SCRATCH/gh_summary" GITHUB_ENV="$SCRATCH/gh_env" \
    REPO="jikig-ai/soleur" PINNED=105149570 PLAINTEXT_VOLUME_NAME=soleur-web-platform-data WEB1_SERVER_ID=123931471 \
    WEB1_SERVER_NAME=soleur-web-platform LUKS_VOLUME_ID=106443278 HCLOUD_TOKEN=hc-ro-token-synth GH_TOKEN=gh-synth \
    "$@" bash --noprofile --norc -eo pipefail "$f" 2>&1)" || RC=$?
}
rm_calls() { grep -c '^terraform state rm ' "$SCRATCH/tf.log" || true; }
leaked() { grep -qF "$SECRET" <<<"$OUT" || grep -qF "$SECRET" "$SCRATCH/gh_output" "$SCRATCH/gh_summary" "$SCRATCH/gh_env" 2>/dev/null; }
# Actions semantics: `forget` only runs when `gone` succeeded.
dispatch() {  # [VAR=value ...] for both steps
  run_step "$SCRATCH/gone.sh" "$@"; GONE_RC="$RC"; GONE_OUT="$OUT"
  if [[ "$GONE_RC" == 0 ]]; then run_step "$SCRATCH/forget.sh" "$@"; else RC="$GONE_RC"; OUT="$GONE_OUT"; fi
}

if [[ -f "$SCRATCH/validate.sh" ]]; then
  vrc() { local r=0; env CONFIRM_IN="$1" PIN_IN="$2" PINNED=105149570 bash --noprofile --norc -eo pipefail "$SCRATCH/validate.sh" >/dev/null 2>&1 || r=$?; printf '%s' "$r"; }
  [[ "$(vrc FORGET-RETIRED-PLAINTEXT-VOLUME 105149570)" == 0 ]] && ok "V1 the exact confirm token + the pinned id pass" || no "V1 the valid inputs were refused"
  [[ "$(vrc FORGET-RETIRED-PLAINTEXT-VOLUME 106443278)" != 0 ]] && ok "V2 an id other than the constant pin (here the LIVE LUKS id) is refused" || no "V2 a non-pin id was accepted"
  [[ "$(vrc CUTOVER-WORKSPACES-LUKS 105149570)" != 0 ]] && ok "V3 a wrong confirm token is refused" || no "V3 a wrong token was accepted"
fi

if [[ -f "$SCRATCH/gone.sh" && -f "$SCRATCH/forget.sh" ]]; then
  # H0 — the happy forget: both web-1 addresses removed, nothing else, serial + 1, lineage kept.
  fx_reset; fx_gone; state_fixture
  dispatch
  post_list="$(jq -r '.resources[] | . as $r | .instances[] | "\($r.type).\($r.name)[\(.index_key // "-")]"' "$SCRATCH/state.json" | sort | tr '\n' ' ')"
  if [[ "$RC" == 0 && "$(rm_calls)" == 1 ]] && grep -qF 'terraform state rm hcloud_volume.workspaces["web-1"] hcloud_volume_attachment.workspaces["web-1"]' "$SCRATCH/tf.log" \
    && [[ "$(jq -r .serial "$SCRATCH/state.json")" == 42 ]] && [[ "$post_list" == *'hcloud_volume.workspaces[web-2]'* ]] \
    && [[ "$post_list" != *'hcloud_volume.workspaces[web-1]'* ]] && [[ "$post_list" == *'hcloud_server.web[web-1]'* ]] \
    && grep -q 'forgot=2' "$SCRATCH/gh_output" && ! leaked; then
    ok "G4-H0 pin 404 + presence proven + identity bound: ONE state rm of exactly the two web-1 addresses; serial 41 -> 42; web-2 and the server untouched; no state byte leaked"
  else
    no "G4-H0 the happy forget failed (rc=$RC rm=$(rm_calls) serial=$(jq -r .serial "$SCRATCH/state.json")) ${OUT:0:300}"
  fi
  fx_reset; fx_gone; state_fixture; fx GET "/volumes/105149570" 0 200 '{"volume":{"id":105149570}}'
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #1 the pinned id still answers 200 → no state rm" || no "G4 #1 a live volume was forgotten (rc=$RC rm=$(rm_calls))"
  fx_reset; fx_gone; state_fixture; fx GET "/volumes?name=soleur-web-platform-data" 0 200 '{"volumes":[{"id":105149571}]}'
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #2 pin 404 but the name lookup still finds a volume (a typo'd pin) → no state rm" || no "G4 #2 a typo'd pin was forgotten"
  fx_reset; fx_gone; state_fixture yes yes yes 999
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #3 the state volume instance id differs from the pin → no state rm" || no "G4 #3 a mismatched state id was forgotten (rc=$RC)"
  fx_reset; fx_gone; state_fixture yes yes yes 105149570 999
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #3b the attachment's volume_id differs from the pin → no state rm" || no "G4 #3b a mismatched attachment was forgotten"
  fx_reset; fx_gone; state_fixture yes yes no
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #4 hcloud_server.web[\"web-1\"] absent (wrong state object) → no state rm" || no "G4 #4 a wrong state object was edited"
  fx_reset; fx_gone; state_fixture
  dispatch TF_RM_EXTRA=1
  [[ "$RC" != 0 ]] && ok "G4 #5 a removal that took anything beyond the two web-1 addresses fails the post-diff" || no "G4 #5 an over-broad removal passed the post-diff"
  fx_reset; fx_gone; state_fixture; fx GET "/servers/123931471" 0 404 '{"error":{"code":"not_found"}}'
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #6b a token that cannot see web-1 (another project) never reads 404 as gone → no state rm" || no "G4 #6b a blind 404 was trusted"
  fx_reset; fx_gone; state_fixture; fx GET "/servers/123931471" 0 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[105149570]}}'
  dispatch
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 #6b' the server not holding the LUKS volume fails the presence proof" || no "G4 #6b' presence proof passed without the LUKS volume"
  fx_reset; fx_gone; state_fixture
  dispatch TF_SERIAL_BUMP=2
  [[ "$RC" != 0 ]] && ok "G4 #6d a post-removal serial other than pre + 1 fails" || no "G4 #6d a serial jump passed"
  fx_reset; fx_gone; state_fixture
  dispatch TF_LINEAGE_CHANGE=1
  [[ "$RC" != 0 ]] && ok "G4 #6d a changed lineage fails (a different state object)" || no "G4 #6d a lineage change passed"
  fx_reset; fx_gone; state_fixture
  dispatch TF_RM_NOOP=1
  [[ "$RC" != 0 ]] && ok "G4 #7 a state rm that removes nothing cannot report success (the post-diff must show the removal)" || no "G4 #7 a no-op state rm reported success"
  fx_reset; fx_gone; state_fixture yes no
  dispatch
  if [[ "$RC" == 0 && "$(rm_calls)" == 1 ]] && grep -qF 'terraform state rm hcloud_volume.workspaces["web-1"]' "$SCRATCH/tf.log" \
    && ! grep -qF 'hcloud_volume_attachment.workspaces["web-1"]' "$SCRATCH/tf.log" && grep -q 'forgot=1' "$SCRATCH/gh_output"; then
    ok "G4-H1 one of the two addresses present → removes exactly that one"
  else
    no "G4-H1 the one-present case failed (rc=$RC) ${OUT:0:200}"
  fi
  fx_reset; fx_gone; state_fixture no no
  dispatch
  [[ "$RC" == 0 && "$(rm_calls)" == 0 && "$OUT" == *already_forgotten* ]] && grep -q 'forgot=0' "$SCRATCH/gh_output" \
    && ok "G4-H2 both already absent → already_forgotten, no mutation" || no "G4-H2 the already-forgotten case failed (rc=$RC rm=$(rm_calls)) ${OUT:0:200}"
  fx_reset; fx_gone; state_fixture
  dispatch GH_STATE_APPLY=active
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 the pause is still real at forget time (an active apply workflow → no state rm)" || no "G4 an active apply workflow did not block the forget"
  fx_reset; fx_gone; state_fixture
  dispatch GH_RUNS_PIPELINE='[{"status":"in_progress"}]'
  [[ "$RC" != 0 && "$(rm_calls)" == 0 ]] && ok "G4 a running apply-deploy-pipeline-fix blocks the forget" || no "G4 a running pipeline-fix did not block the forget"
  fx_reset; fx_gone; state_fixture
  dispatch
  ! grep -q 'hc-ro-token-synth' "$SCRATCH/curl.log" && grep -q 'hc-ro-token-synth' "$SCRATCH/curl.cfg" \
    && ok "G4 the Hetzner token rides --config on stdin, never curl argv" || no "G4 the token reached curl argv (or never reached curl)"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
# PASS FLOOR at the measured count.
FORGET_MIN_PASS=47
if [[ "$pass" -lt "$FORGET_MIN_PASS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a row was dropped or stopped dispatching\n' "$pass" "$FORGET_MIN_PASS"
  exit 1
fi
[[ "$fail" -eq 0 ]]
