#!/usr/bin/env bash
# Drift, behaviour and mutation guard for the key rotation route (#11294, ADR-314): .github/workflows/key-rotate.yml and its body
# scripts/key-rotate.sh (which SOURCES scripts/inngest-key-rotate.sh and overrides what differs; the sibling suite
# inngest-key-rotate-workflow.test.sh stays green and unchanged).
#
# WHAT THIS PROTECTS. The route rotates ONE secret per dispatch on a public repository. The failures that matter are silent or
# irreversible: key bytes in a PUBLIC log (Terraform prints a random_id's id, which IS the key in base64url, and the full plan JSON
# holds every root variable), a write that runs although a precondition failed, a plan that touches an address outside the chosen
# key's rows, an Inngest-route sentence or a `converge` command leaking from the sourced script, and a half-finished rotation that
# nobody owns. Layers:
#   A. STATIC, on the PARSED workflow (parsed once to JSON, queried with jq; job conditions EVALUATED, never substring-matched).
#   B. STATIC, on the script: type-checked sourced symbols, the override points, one Terraform chokepoint, the verdict-token set,
#      a sha256 over the sourced bodies the script depends on, a credential-free --print-contract.
#   C. BEHAVIOUR against stubs (gh, doppler, terraform, ssh-keygen, track.sh): every refusal rung, plan for all seven keys, rotate for
#      the six rotatable keys, the H1 absent paths, post-state precedence, redeploy and notify, and the no-stream test (a stub terraform
#      prints key-shaped strings on BOTH streams; every stream of every scenario is scanned and the scan count must equal the run count).
#   D. MUTATIONS (Guard Contract 1-4): each guard is removed in a COPY and the scenario that depends on it must change from "stops" to
#      "proceeds" (a guard no scenario can see is not a guard), plus harness rows. Guard 5 (table versus HCL) lives in
#      plugins/soleur/test/terraform-target-parity.test.ts.
# Every oracle below is a LITERAL, never derived from the script under test. Every date and window read goes through the script's
# single clock (KR_NOW). Fixtures are synthesized (cq-test-fixtures-synthesized-only): token-shaped values are built by concatenation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/key-rotate.yml"
BODY="$REPO_ROOT/scripts/key-rotate.sh"
SIB="$REPO_ROOT/scripts/inngest-key-rotate.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR%/}/key-rotate-wf.XXXXXX")" || { echo "FAIL SETUP: mktemp"; exit 1; }
assert_fixture_dir "$TMP"
trap 'rm -rf -- "$TMP"' EXIT

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL SETUP: python3 yaml unavailable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL SETUP: jq unavailable"; exit 1; }
for f in "$WF" "$BODY" "$SIB"; do [[ -f "$f" ]] || { echo "FAIL SETUP: $f missing"; exit 1; }; done

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; return 0; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# eq <description> <got> <want>
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "got '${2:0:300}' want '${3:0:300}'"; fi; }

# INSTRUMENT SELF-TEST: drive both helpers once and require both counters to move before any row is believed.
_p0=$PASS; _f0=$FAIL
ok "self-test: ok() increments PASS" >/dev/null; bad "self-test: bad() increments FAIL" >/dev/null
if (( PASS == _p0 + 1 && FAIL == _f0 + 1 )); then PASS=$_p0; FAIL=$_f0; else printf 'FAIL INSTRUMENT: ok()/bad() did not move their counters\n' >&2; exit 2; fi

# ---------------------------------------------------------------------------------------------------------------------------
# LITERAL ORACLES (never derived from the script under test).
SYMBOL_FUNCS="kr_tf kr_init kr_tf_prepare kr_scrub kr_gate_rows kr_gate_targets kr_gate_replaces kr_gate_want kr_refuse kr_ok kr_inflight_check kr_chk_attempt kr_chk_quiet kr_summary kr_out kr_token_known kr_now kr_iso kr_sleep kr_post_write_failure"
SYMBOL_ARRAYS="KR_GATE_TABLE KR_INFLIGHT_WORKFLOWS KR_VERDICT_TOKENS"
SYMBOL_SCALARS="KR_GATE_JQ KR_CHANGED"
# the sourced bodies the script calls, plus their transitive callees (kr_init -> kr_cleanup; kr_post_write_failure -> the overridden pair)
SOURCED_CALLED="kr_tf kr_init kr_cleanup kr_tf_prepare kr_scrub kr_gate_rows kr_gate_targets kr_gate_replaces kr_gate_want kr_inflight_check kr_chk_attempt kr_chk_quiet kr_summary kr_token_known kr_now kr_iso kr_sleep kr_post_write_failure"
SOURCED_PIN="77a69115390b4ff945b1033d45145120d896f05a15a71e3066d32e1394a8a5bb"
OVERRIDES="kr_refuse kr_ok kr_print_contract main kr_chk_confirm kr_stop_sentence kr_post_write_stop kr_file_issue kr_verdict_recipe kr_converge_cmd kr_cmd_notify"
KEYS="inngest_manual_trigger_secret_dev inngest_manual_trigger_secret_prd inngest_signing_key_dev inngest_event_key_dev kb_drift_ingest_signing_key egress_audit_ingest_token github_webhook_secret"
ROTATABLE="inngest_manual_trigger_secret_dev inngest_manual_trigger_secret_prd inngest_signing_key_dev inngest_event_key_dev kb_drift_ingest_signing_key github_webhook_secret"
# key|project|config|name : the copies each key's value lives in (the HCL is the independent side, Guard 5)
COPIES_LIT="inngest_manual_trigger_secret_dev|soleur|dev|INNGEST_MANUAL_TRIGGER_SECRET
inngest_manual_trigger_secret_prd|soleur|prd|INNGEST_MANUAL_TRIGGER_SECRET
inngest_signing_key_dev|soleur|dev|INNGEST_SIGNING_KEY
inngest_event_key_dev|soleur|dev|INNGEST_EVENT_KEY
kb_drift_ingest_signing_key|soleur|prd_kb_drift_walker|KB_DRIFT_INGEST_SIGNING_KEY
kb_drift_ingest_signing_key|soleur|prd|KB_DRIFT_INGEST_SIGNING_KEY
egress_audit_ingest_token|soleur|prd|EGRESS_AUDIT_INGEST_TOKEN
github_webhook_secret|soleur|prd|GITHUB_APP_WEBHOOK_SECRET"
# the four secrets that carry lifecycle.ignore_changes=[value] (their rows are replace-both); the other three update in place
IGNORE_SET="doppler_secret.inngest_manual_trigger_secret_dev doppler_secret.inngest_manual_trigger_secret_prd doppler_secret.inngest_signing_key_dev doppler_secret.inngest_event_key_dev"
TOKENS="guard_ok ref_refused inputs_invalid actor_refused actor_not_owner rerun_refused confirm_mismatch quiet_window_missing egress_rotate_unsupported_no_vector_restart_lever approval_environment_missing webhook_patch_not_ready owner_step_open kb_drift_cron_window kb_drift_walker_in_flight run_in_flight run_list_unreadable redaction_coverage_unconfirmed credential_absent authorization_stale copy_unreadable partial_absent_state plan_ok plan_gate_refused replace_not_requested terraform_failed apply_failed post_hash_unreadable value_unchanged copies_differ rotated_redeploy_failed owner_step_pending issue_unfiled rotate_ok job_cancelled internal_error"
# tokens only the SOURCED code emits (the script reaches them through kr_chk_attempt, kr_chk_quiet and kr_tf_prepare)
TOKENS_SOURCED_ONLY="rerun_refused quiet_window_missing credential_absent"
PROJECTED_FIELDS="address actions action_reason before_null after_unknown_value"
OWNER_LOGIN="deruelle"
# budgets in whole minutes: guard step/job, apply step/job, redeploy step/job, notify step/job
MIN_GUARD_STEP=15; MIN_GUARD_JOB=25; MIN_APPLY_STEP=40; MIN_APPLY_JOB=50; MIN_REDEPLOY_STEP=85; MIN_REDEPLOY_JOB=95; MIN_NOTIFY_STEP=5; MIN_NOTIFY_JOB=15
ROWS_KB=3; ROWS_OTHER=2
SHA256_OF() { sha256sum | cut -c1-64; }

# ---------------------------------------------------------------------------------------------------------------------------
# Synthesized sentinels: shaped like key material, built by concatenation, independent of the script's own scrub patterns.
S_B64="$(printf 'Zq3Xk9Lm2Pw7Rt5Vb8Yn1Hj4Gc6Fd0SaUe_Zq3Xk9Lm2Pw7' | cut -c1-43)"      # 43 chars of base64url (a random_id id)
S_HEX="$(printf '9f3a%.0s' {1..16})"                                              # 64 hex (a random_id hex)
S_SIGN="signkey-test-${S_HEX}"
S_STD="$(printf 'Qw3+Er5/Ty7+Ui9/Op1+As3/Df5+Gh7/Jk9+Lz1/Xc3+Vb5' | cut -c1-44)"               # 44 chars of standard base64 with + and /
S_TOKV="dp.st.$(printf 'ab12%.0s' {1..10})"                                       # a token-shaped root-variable value
OLD_PFX="old$(printf 'c3%.0s' {1..20})"

# ---------------------------------------------------------------------------------------------------------------------------
printf '\n=== A. static: the workflow (parsed once to JSON) ===\n'
python3 - "$WF" > "$TMP/wf.json" <<'PY'
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1]))
if True in d: d["on"] = d.pop(True)
print(json.dumps(d))
PY
[[ -s "$TMP/wf.json" ]] && jq -e . "$TMP/wf.json" >/dev/null 2>&1 || { echo "FAIL SETUP: the workflow does not parse"; exit 1; }
wq() { jq -r "$1" "$TMP/wf.json"; }
wqc() { jq -S -c "$1" "$TMP/wf.json"; }

eq "A1 triggers are exactly workflow_dispatch plus a registration push" "$(wqc '.on | keys')" '["push","workflow_dispatch"]'
eq "A2 the push trigger is main-only and scoped to this file alone" "$(wqc '.on.push | [.branches, .paths]')" '[["main"],[".github/workflows/key-rotate.yml"]]'
eq "A3 the jobs are exactly guard, apply, redeploy, notify" "$(wqc '.jobs | keys')" '["apply","guard","notify","redeploy"]'
eq "A4 every job carries an if: (its truth is EVALUATED in A20-A21, not matched as text)" "$(wqc '[.jobs[] | has("if")] | all')" 'true'
eq "A5 the dispatch inputs are mode, key, confirm, quiet_window, webhook_patch_ready (no reason input)" "$(wqc '.on.workflow_dispatch.inputs | keys')" '["confirm","key","mode","quiet_window","webhook_patch_ready"]'
eq "A6 mode is {plan, rotate} and key is the seven names, both required with no default" "$(wqc '.on.workflow_dispatch.inputs | [.mode.options, .key.options, .mode.required, .key.required, (.mode|has("default")), (.key|has("default"))]')" \
  '[["plan","rotate"],["inngest_manual_trigger_secret_dev","inngest_manual_trigger_secret_prd","inngest_signing_key_dev","inngest_event_key_dev","kb_drift_ingest_signing_key","egress_audit_ingest_token","github_webhook_secret"],true,true,false,false]'
eq "A7 quiet_window and webhook_patch_ready are booleans that default to false" "$(wqc '.on.workflow_dispatch.inputs | [.quiet_window, .webhook_patch_ready] | map([.type, .default])')" '[["boolean",false],["boolean",false]]'
eq "A8 run-name starts with key-rotate (inngest-link-flip.sh Guard 3 keys on ^inngest-key-rotate plan)" "$(wq '."run-name"')" 'key-rotate ${{ inputs.mode }} ${{ inputs.key }}'
check "A9 run-name does not match ^inngest-key-rotate" bash -c "! jq -e '.\"run-name\" | test(\"^inngest-key-rotate\")' '$TMP/wf.json'"
eq "A10 workflow permissions are contents:read; each job widens only what it needs" "$(wqc '.permissions')" '{"contents":"read"}'
eq "A11 only the notify job holds issues:write; the guard reads issues; the write jobs hold no issues scope" "$(wqc '[.jobs[] | .permissions.issues // "none"] ')" '["read","none","none","write"]'
eq "A12 per-job permissions are the exact closed sets" "$(wqc '.jobs | [.guard.permissions, .apply.permissions, .redeploy.permissions, .notify.permissions]')" \
  '[{"actions":"read","contents":"read","issues":"read"},{"actions":"read","contents":"read"},{"actions":"read","contents":"read"},{"issues":"write"}]'
eq "A13 every remote action is pinned to a 40-hex SHA" "$(wqc '[.jobs[].steps[] | select(has("uses")) | .uses | select(startswith("./") | not) | split("@")[1] | split(" ")[0] | length == 40] | all')" 'true'
eq "A14 the action set is checkout, setup-terraform and the credential loader (no Doppler CLI action, no artifact or cache action)" "$(wqc '[.jobs[].steps[] | select(has("uses")) | .uses | split("@")[0]] | unique')" '["./.github/actions/infra-credentials","actions/checkout","hashicorp/setup-terraform"]'
eq "A15 no expression of any kind is interpolated into a run: body (everything arrives through env:)" "$(wqc '[.jobs[].steps[] | select(has("run")) | .run | contains("${{")] | any')" 'false'
eq "A16 no job condition reads a dispatch input (conditions read the guard's validated outputs)" "$(wqc '[.jobs[] | .if | tostring | contains("inputs.")] | any')" 'false'
eq "A17 every checkout drops its credentials" "$(wqc '[.jobs[].steps[] | select((.uses // "") | startswith("actions/checkout")) | .with["persist-credentials"]] | unique')" '[false]'
eq "A18 no continue-on-error anywhere" "$(wqc '[.. | objects | select(has("continue-on-error"))] | length')" '0'
check "A19 nothing is uploaded: no upload-artifact, no cache step, and no Terraform stream redirected to the summary" bash -c "! grep -Eq 'upload-artifact|actions/cache|GITHUB_STEP_SUMMARY' '$WF'"

# The job conditions as a PROGRAM: a small GitHub-expression evaluator (|| && ! == != parentheses, string literals, contexts, always() /
# cancelled() / success()), COPIED from inngest-key-rotate-workflow.test.sh section W (same grammar; this workflow has different jobs,
# outputs and scenarios). The table below is the expected evaluation; a swapped output or an `always() ||` changes a row.
cat > "$TMP/wfeval.py" <<'PY'
import re, sys, json
d = json.load(open(sys.argv[1])); jobs = d["jobs"]; mode = sys.argv[2]
ORDER = ["guard", "apply", "redeploy", "notify"]
STATUS = {"always", "cancelled", "failure", "success"}
def tokenize(src):
    toks, i = [], 0
    while i < len(src):
        c = src[i]
        if c.isspace(): i += 1; continue
        if src[i:i+2] in ("&&", "||", "==", "!="): toks.append(src[i:i+2]); i += 2; continue
        if c in "()!": toks.append(c); i += 1; continue
        if c == "'": j = src.index("'", i + 1); toks.append(("s", src[i+1:j])); i = j + 1; continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_.\-]*", src[i:])
        if not m: raise ValueError("unexpected %r" % c)
        toks.append(("i", m.group(0))); i += len(m.group(0))
    return toks
class P:
    def __init__(s, toks, ctx): s.t, s.k, s.ctx, s.used = toks, 0, ctx, set()
    def peek(s): return s.t[s.k] if s.k < len(s.t) else None
    def eat(s): v = s.t[s.k]; s.k += 1; return v
    def parse(s):
        v = s.o()
        if s.peek() is not None: raise ValueError("trailing")
        return v
    def o(s):
        v = s.a()
        while s.peek() == "||": s.eat(); r = s.a(); v = v if v else r
        return v
    def a(s):
        v = s.e()
        while s.peek() == "&&": s.eat(); r = s.e(); v = r if v else v
        return v
    def e(s):
        v = s.u()
        if s.peek() in ("==", "!="):
            op = s.eat(); r = s.u(); eq = str(v).lower() == str(r).lower(); return eq if op == "==" else not eq
        return v
    def u(s):
        if s.peek() == "!": s.eat(); return not s.u()
        return s.p()
    def p(s):
        t = s.eat()
        if t == "(": v = s.o(); assert s.eat() == ")"; return v
        if isinstance(t, tuple) and t[0] == "s": return t[1]
        if isinstance(t, tuple) and t[0] == "i":
            if s.peek() == "(":
                s.eat(); assert s.eat() == ")"; s.used.add(t[1]); return s.ctx["fn"](t[1])
            return s.ctx["var"](t[1])
        raise ValueError("bad token %r" % (t,))
def expr(cond, var, fn):
    src = str(cond).strip(); m = re.fullmatch(r"\$\{\{(.*)\}\}", src, re.S)
    p = P(tokenize(m.group(1) if m else src), {"var": var, "fn": fn}); return bool(p.parse()), p.used
def run(scn):
    res = {}; outs = {}
    for j in ORDER:
        needs = jobs[j].get("needs", []); needs = [needs] if isinstance(needs, str) else list(needs)
        def var(name):
            if name == "github.event_name": return scn["event"]
            if name == "github.run_id": return "RUNID"
            if name in ("true", "false"): return name == "true"
            m = re.fullmatch(r"needs\.([a-z0-9]+)\.result", name)
            if m: return res.get(m.group(1), "skipped")
            m = re.fullmatch(r"needs\.([a-z0-9]+)\.outputs\.([a-z_0-9]+)", name)
            if m: return outs.get(m.group(1), {}).get(m.group(2), "")
            raise ValueError("unknown context " + name)
        def fn(name):
            if name == "always": return True
            if name == "cancelled": return False
            if name == "success": return all(res.get(n) == "success" for n in needs)
            raise ValueError("unknown function " + name)
        ok, used = expr(jobs[j]["if"], var, fn)
        if not (used & STATUS) and not all(res.get(n) == "success" for n in needs): ok = False
        if j == "guard": res[j] = scn.get("guard_result", "success") if ok else "skipped"
        else: res[j] = scn.get("force", {}).get(j, "success") if ok else "skipped"
        if j == "guard" and res[j] != "skipped": outs[j] = scn["gout"]
        if j == "apply": outs[j] = {"write_started": "true"}
        if j == "redeploy": outs[j] = {"verdict": "rotate_ok"}
    return res
PLAN = {"go": "true", "mode": "plan", "run_apply": "true", "run_redeploy": "false", "redaction_ok": "true"}
ROT = {"go": "true", "mode": "rotate", "run_apply": "true", "run_redeploy": "true", "redaction_ok": "true"}
D = "workflow_dispatch"
SC = [
 ("plan", dict(event=D, gout=PLAN)),
 ("rotate", dict(event=D, gout=ROT)),
 ("rotate/apply-fails", dict(event=D, gout=ROT, force={"apply": "failure"})),
 ("rotate/apply-cancelled", dict(event=D, gout=ROT, force={"apply": "cancelled"})),
 ("rotate/redeploy-fails", dict(event=D, gout=ROT, force={"redeploy": "failure"})),
 ("rotate/redaction-not-ok", dict(event=D, gout=dict(ROT, redaction_ok="false"))),
 ("rotate/redaction-missing", dict(event=D, gout={k: v for k, v in ROT.items() if k != "redaction_ok"})),
 ("guard-refused", dict(event=D, gout={"go": "false"}, guard_result="failure")),
 ("guard-ok-no-go", dict(event=D, gout=dict(ROT, go="false"))),
 ("push", dict(event="push", gout={})),
]
for name, scn in SC:
    r = run(scn)
    print("%-26s %s" % (name, " ".join("%s=%s" % (j, r[j]) for j in ORDER)))
PY
cat > "$TMP/matrix.expected" <<'EOF'
plan                       guard=success apply=success redeploy=skipped notify=skipped
rotate                     guard=success apply=success redeploy=success notify=success
rotate/apply-fails         guard=success apply=failure redeploy=skipped notify=success
rotate/apply-cancelled     guard=success apply=cancelled redeploy=skipped notify=success
rotate/redeploy-fails      guard=success apply=success redeploy=failure notify=success
rotate/redaction-not-ok    guard=success apply=skipped redeploy=skipped notify=success
rotate/redaction-missing   guard=success apply=skipped redeploy=skipped notify=success
guard-refused              guard=failure apply=skipped redeploy=skipped notify=skipped
guard-ok-no-go             guard=success apply=skipped redeploy=skipped notify=skipped
push                       guard=skipped apply=skipped redeploy=skipped notify=skipped
EOF
matrix_of() { python3 "$TMP/wfeval.py" "$1" x 2>&1; }
MATRIX_NOW="$(matrix_of "$TMP/wf.json")"
eq "A20 the evaluated job matrix: plan runs guard and apply only; rotate runs all four; apply needs redaction_ok; notify runs after every outcome of a rotate (never plan, never a refused guard, never a push)" "$MATRIX_NOW" "$(cat "$TMP/matrix.expected")"
# A21: matrix mutants (a substring check passes each of these; the evaluated matrix does not)
wf_variant() { # name jq-filter -> $TMP/wfv-<name>.json
  jq -c "$2" "$TMP/wf.json" > "$TMP/wfv-$1.json"
}
wf_variant if_always '.jobs.apply.if = "${{ always() || (needs.guard.outputs.go == '"'"'true'"'"') }}"'
wf_variant no_redaction '.jobs.apply.if |= sub(" && needs.guard.outputs.redaction_ok == '"'"'true'"'"'"; "")'
wf_variant notify_plan '.jobs.notify.if |= sub(" && needs.guard.outputs.mode == '"'"'rotate'"'"'"; "")'
wf_variant no_dispatch '.jobs.guard.if = "${{ true }}"'
wf_variant redeploy_nosuccess '.jobs.redeploy.if |= sub(" && needs.apply.result == '"'"'success'"'"'"; "")'
for v in if_always no_redaction notify_plan no_dispatch redeploy_nosuccess; do
  [[ "$(matrix_of "$TMP/wfv-$v.json")" != "$MATRIX_NOW" ]] && ok "A21 matrix mutant $v changes the evaluated matrix" || bad "A21 matrix mutant $v is invisible to the evaluated matrix"
done
eq "A22 timeouts are the literals of the budget (guard 15/25, apply 40/50, redeploy 85/95, notify 5/15 minutes)" \
  "$(wqc '[.jobs.guard."timeout-minutes", (.jobs.guard.steps[] | select(.id == "guard") | ."timeout-minutes"), .jobs.apply."timeout-minutes", (.jobs.apply.steps[] | select(.id == "apply") | ."timeout-minutes"), .jobs.redeploy."timeout-minutes", (.jobs.redeploy.steps[] | select(.id == "track") | ."timeout-minutes"), .jobs.notify."timeout-minutes", (.jobs.notify.steps[] | select(has("run")) | ."timeout-minutes")]')" \
  "[$MIN_GUARD_JOB,$MIN_GUARD_STEP,$MIN_APPLY_JOB,$MIN_APPLY_STEP,$MIN_REDEPLOY_JOB,$MIN_REDEPLOY_STEP,$MIN_NOTIFY_JOB,$MIN_NOTIFY_STEP]"
eq "A23 every run and loader step carries its own timeout-minutes" "$(wqc '[.jobs[].steps[] | select(has("run") or ((.uses // "") | startswith("./"))) | has("timeout-minutes")] | all')" 'true'
eq "A24 concurrency: dispatch group is the literal inngest-key-rotate (mutual exclusion with the sibling), the push run gets a distinct group, nothing cancels in progress" \
  "$(wqc '[.concurrency."cancel-in-progress", ([.jobs[] | .concurrency."cancel-in-progress"? ] | map(select(. != null)) | all(. == false))]')" '[false,true]'
cat > "$TMP/grp.py" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
def ev(expr, event, mode):
    m = re.fullmatch(r"\$\{\{(.*)\}\}", expr.strip(), re.S)
    if not m: return expr.strip()
    s = m.group(1).strip()
    # A && 'x' || 'y'  /  A && 'x' || github.run_id
    mm = re.fullmatch(r"(.+?)\s*&&\s*'([^']*)'\s*\|\|\s*(?:'([^']*)'|github\.run_id)", s)
    assert mm, s
    cond, a, b = mm.group(1), mm.group(2), mm.group(3)
    lhs, rhs = re.fullmatch(r"(\S+)\s*==\s*'([^']*)'", cond).groups()
    val = {"github.event_name": event, "needs.guard.outputs.mode": mode}[lhs]
    return a if val == rhs else (b if b is not None else "RUNID")
wf = d["concurrency"]["group"]; ap = d["jobs"]["apply"]["concurrency"]["group"]; rd = d["jobs"]["redeploy"]["concurrency"]["group"]
print(ev(wf, "workflow_dispatch", ""), ev(wf, "push", ""), ev(ap, "workflow_dispatch", "rotate"), ev(ap, "workflow_dispatch", "plan"), rd)
PY
eq "A25 groups EVALUATED: dispatch=inngest-key-rotate, push=key-rotate-registration, apply=terraform-apply-web-platform-host for rotate only (a plan gets a per-run group), redeploy=web-1-swap" \
  "$(python3 "$TMP/grp.py" "$TMP/wf.json" 2>&1)" "inngest-key-rotate key-rotate-registration terraform-apply-web-platform-host RUNID web-1-swap"
eq "A26 environments: only the apply job runs in infra-privileged (the Tier-B environment); guard, redeploy and notify hold none" "$(wqc '[.jobs[] | .environment // "none"]')" '["none","infra-privileged","none","none"]'
eq "A27 the credential loader runs in the apply job only" "$(wqc '[.jobs[] | [.steps[] | select((.uses // "") | startswith("./.github/actions/infra-credentials"))] | length]')" '[0,1,0,0]'
SECRETS_OF() { jq -r --arg j "$1" '[.jobs[$j] | tostring | scan("secrets\\.([A-Z0-9_]+)") | .[0]] | unique | join(",")' "$TMP/wf.json"; }
eq "A28 secrets by job: the guard holds none; apply holds the Tier-A token and the loader token; redeploy holds the deploy webhook trio only; notify none" \
  "$(SECRETS_OF guard)|$(SECRETS_OF apply)|$(SECRETS_OF redeploy)|$(SECRETS_OF notify)" "|DOPPLER_TOKEN,DOPPLER_TOKEN_INFRA_PRIVILEGED|CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET,WEBHOOK_DEPLOY_SECRET|"
eq "A29 every use of the secrets context is the dotted form secrets.NAME" "$(grep -oE 'secrets[^.A-Za-z_]|secrets$' "$WF" | wc -l | tr -d ' ')" '0'
# The trio (CTO F7): in exactly ONE step's env of exactly the redeploy job (the track.sh step), with no GH_TOKEN and no Doppler token there.
eq "A30 the deploy trio appears in exactly one step's env: the redeploy job's track step; that step holds no GH_TOKEN and no Doppler token" \
  "$(wqc '[.jobs | to_entries[] | .key as $j | .value.steps[] | select(.env // {} | keys | any(. == "WEBHOOK_DEPLOY_SECRET" or . == "CF_ACCESS_CLIENT_ID" or . == "CF_ACCESS_CLIENT_SECRET")) | [$j, .id, (.env | keys)]]')" \
  '[["redeploy","track",["CF_ACCESS_CLIENT_ID","CF_ACCESS_CLIENT_SECRET","WEBHOOK_DEPLOY_SECRET"]]]'
eq "A31 the trio is not at workflow or job level and the apply job never names it" "$(wqc '[(.env // {} | keys), (.jobs | to_entries[] | .value.env // {} | keys)] | flatten | map(select(test("WEBHOOK_DEPLOY|CF_ACCESS"))) | length')|$(grep -c 'WEBHOOK_DEPLOY\|CF_ACCESS' <(wqc '.jobs.apply'))" '0|0'
eq "A32 WEB_HOST_PRIVATE_IPS is the pinned literal in the redeploy job env (web-hosts-fanout-parity.test.sh compares it with var.web_hosts)" "$(wq '.jobs.redeploy.env.WEB_HOST_PRIVATE_IPS')" '10.0.1.10,10.0.1.11'
eq "A33 the redeploy job's three steps run in the order: re-checks, track, verdict; the verdict step always runs and the track step needs the re-checks" \
  "$(wqc '[.jobs.redeploy.steps[] | select(has("id")) | [.id, (.if // "")]]')" '[["recheck",""],["track","${{ steps.recheck.outcome == '"'"'success'"'"' }}"],["final","${{ always() }}"]]'
eq "A34 the apply step holds no deploy webhook secret and no write-scoped token; its GH_TOKEN is the job token under actions:read" "$(wq '.jobs.apply.steps[] | select(.id == "apply") | .env.GH_TOKEN')" '${{ github.token }}'
eq "A35 the guard job's redaction step is after checkout and before the ladder, holds no env at all (no GH_TOKEN, no secrets), and the ladder step is last" \
  "$(wqc '[.jobs.guard.steps[] | [(.id // "-"), ((.env // {}) | keys | length)]]')" '[["-",0],["pre",0],["guard",6]]'
eq "A36 the guard job exports go, mode, key, run_apply, run_redeploy, guard_epoch and redaction_ok (redaction_ok from the redaction step, the rest from the ladder)" "$(wqc '.jobs.guard.outputs | to_entries | map([.key, (.value | capture("steps\\.(?<s>[a-z]+)\\.").s)])')" \
  '[["go","guard"],["mode","guard"],["key","guard"],["run_apply","guard"],["run_redeploy","guard"],["guard_epoch","guard"],["redaction_ok","pre"]]'
eq "A37 the run bodies are exactly one script subcommand each" "$(wqc '[.jobs[].steps[] | select(has("run")) | .run | gsub("\\s+$"; "")]')" \
  '["bash scripts/key-rotate.sh precondition","bash scripts/key-rotate.sh guard","bash scripts/key-rotate.sh apply","bash scripts/key-rotate.sh redeploy recheck","bash scripts/key-rotate.sh redeploy track","bash scripts/key-rotate.sh redeploy verdict","bash scripts/key-rotate.sh notify"]'
eq "A38 setup-terraform is present with the pinned TERRAFORM_VERSION (positive row for the scoped Terraform check) and the apply step is the only Terraform-running step" \
  "$(wqc '[(.env.TERRAFORM_VERSION), ([.jobs.apply.steps[] | select((.uses // "") | startswith("hashicorp/setup-terraform"))] | length)]')" '["1.10.5",1]'
# The scoped Terraform check: PARSED run: bodies only, command-position regex, closed set; bypass-shape control rows prove the regex sees them.
TF_RE='(^|[;&|(]|[[:space:]])(command[[:space:]]+|env[[:space:]]+|exec[[:space:]]+|sudo[[:space:]]+)?(\$TF|\$\{TF\}|terraform)[[:space:]]+(init|plan|apply|show|refresh|destroy|import|state|output|console|-chdir)'
tf_hits_in_runs() { jq -r '.jobs[].steps[] | select(has("run")) | .run' "$1" | grep -Ec "$TF_RE" || true; }
eq "A39 no run: body of the workflow runs a Terraform command (command-position regex over PARSED run bodies; the script is the only caller)" "$(tf_hits_in_runs "$TMP/wf.json")" '0'
wf_variant tf_plan '.jobs.apply.steps += [{"run": "terraform plan -out=x"}]'
wf_variant tf_command '.jobs.apply.steps += [{"run": "command terraform apply"}]'
wf_variant tf_var '.jobs.apply.steps += [{"run": "$TF plan"}]'
wf_variant tf_env '.jobs.apply.steps += [{"run": "env terraform show -json p"}]'
for v in tf_plan tf_command tf_var tf_env; do
  [[ "$(tf_hits_in_runs "$TMP/wfv-$v.json")" == 1 ]] && ok "A40 control: the Terraform check sees the bypass shape $v" || bad "A40 control: the Terraform check misses $v"
done
wf_variant upload '.jobs.apply.steps += [{"uses": "actions/upload-artifact@v4"}]'
[[ "$(jq -r '[.jobs[].steps[] | (.uses // "") | select(startswith("actions/upload-artifact"))] | length' "$TMP/wfv-upload.json")" == 1 ]] && ok "A41 control: the upload check sees an upload-artifact step" || bad "A41 control: upload check blind"
check "A42 the workflow header states: dispatch-only, a production act, the typed confirm is a fat-finger guard and not the authorization, the repository is public" bash -c "grep -qi 'dispatch-only' '$WF' && grep -qi 'production act' '$WF' && grep -qi 'fat-finger' '$WF' && grep -qi 'repository is public' '$WF'"

# ---------------------------------------------------------------------------------------------------------------------------
printf '\n=== B. static: the script ===\n'
check "B1 the script parses clean (bash -n)" bash -n "$BODY"
if command -v shellcheck >/dev/null 2>&1; then check "B2 shellcheck is clean" shellcheck "$BODY"; else ok "B2 shellcheck not installed; skipped"; fi
code_only() { grep -v '^ *#' "$1" | sed -E 's/^([^"'"'"']*[^"'"'"' ]) +#[^"'"'"']*$/\1/'; }
# fn_range <file> <name>: first and last line of a top-level function (a one-line definition is its own range)
fn_range() {
  awk -v n="$2" '$0 ~ "^"n"\\(\\) \\{" { s = NR; if ($0 ~ /\}[[:space:]]*$/ && $0 !~ /\{[[:space:]]*$/) { print s, NR; exit } f = 1; next } f && /^}/ { print s, NR; exit }' "$1"
}
fn_text() { local r; r="$(fn_range "$2" "$1")"; [[ -n "$r" ]] || return 1; sed -n "${r% *},${r#* }p" "$2"; }
# --- symbols: the list is a LITERAL here; the script's own list must equal it, and the sibling must define each with that type
SCRIPT_FUNCS="$(sed -n '/^KK_SYMBOL_FUNCS=(/,/)$/p' "$BODY" | tr -d '\n' | sed -E 's/^KK_SYMBOL_FUNCS=\(//; s/\)$//; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
eq "B3 the script's type-checked function list equals the literal list (20 names)" "$SCRIPT_FUNCS" "$SYMBOL_FUNCS"
SIB_TYPES="$(env -i PATH="$PATH" bash -c '
  source "$1"
  for f in $2; do declare -F "$f" >/dev/null && printf "F:%s\n" "$f" || printf "MISSING-F:%s\n" "$f"; done
  for a in $3; do [[ "$(declare -p "$a")" == "declare -a "* ]] && printf "A:%s\n" "$a" || printf "BAD-A:%s\n" "$a"; done
  for s in $4; do [[ "$(declare -p "$s")" == "declare -- "* ]] && printf "S:%s\n" "$s" || printf "BAD-S:%s\n" "$s"; done' _ "$SIB" "$SYMBOL_FUNCS" "$SYMBOL_ARRAYS" "$SYMBOL_SCALARS" 2>&1)"
eq "B4 the sibling defines every one of those symbols with the expected type (functions; writable arrays; scalars)" "$(grep -cE '^(F|A|S):' <<<"$SIB_TYPES")|$(grep -cE '^(MISSING|BAD)' <<<"$SIB_TYPES")" "$(( $(wc -w <<<"$SYMBOL_FUNCS") + $(wc -w <<<"$SYMBOL_ARRAYS") + $(wc -w <<<"$SYMBOL_SCALARS") ))|0"
SRC_LN="$(grep -n '^source ' "$BODY" | head -1 | cut -d: -f1)"; FIRST_FN="$(grep -nE '^[a-z_]+\(\) \{' "$BODY" | head -1 | cut -d: -f1)"
eq "B5 exactly one top-level source of the sibling, before every function definition" "$(grep -c '^source ' "$BODY")|$([[ -n "$SRC_LN" && -n "$FIRST_FN" && "$SRC_LN" -lt "$FIRST_FN" ]] && echo before)" '1|before'
PRE_LN="$(grep -n 'compgen -v' "$BODY" | head -1 | cut -d: -f1)"
eq "B6 the ^K[RK]_ refusal runs BEFORE the source (the loader exports a whole Doppler project and the sourced file assigns KR_*)" "$([[ -n "$PRE_LN" && "$PRE_LN" -lt "$SRC_LN" ]] && echo before)" 'before'
pre_rc() { env -i PATH="$PATH" HOME="$TMP" GITHUB_ACTIONS=true "$@" bash "$BODY" --print-contract >"$TMP/pre.out" 2>&1; echo $?; }
eq "B7 under GITHUB_ACTIONS=true a stray KR_ name, a stray KK_ name each exit 78; a clean environment does not" "$(pre_rc KR_STRAY=1)|$(pre_rc KK_STRAY=1)|$(pre_rc A_OTHER=1)" '78|78|0'
B7_OUT="$(env -i PATH="$PATH" HOME="$TMP" GITHUB_ACTIONS=true KR_STRAY=sekret-value bash "$BODY" --print-contract 2>&1)"
eq "B7b the refusal names the variable and prints no value" "$(grep -c 'KR_STRAY' <<<"$B7_OUT")|$(grep -c 'sekret-value' <<<"$B7_OUT")" '1|0'
eq "B8 no set -e in any form and no trap in the script (the sourced kr_init owns the EXIT trap that removes the key-bearing temp files)" "$(code_only "$BODY" | grep -Ec '(^|[[:space:];])set +-[a-zA-Z]*e|(^|[[:space:];])trap ')" '0'
eq "B9 no terraform command anywhere in the script: the sourced kr_tf is the one chokepoint" "$(code_only "$BODY" | grep -Ec '(^|[^_a-zA-Z-])terraform[[:space:]]+(init|plan|apply|show|state|output|refresh|destroy|import|console)')|$(code_only "$BODY" | grep -c 'doppler run')" '0|0'
eq "B10 kr_tf is called for plan, show and apply only" "$(code_only "$BODY" | grep -oE 'kr_tf +"?(plan|show|apply)' | sed -E 's/kr_tf +"?//' | sort | tr '\n' ' ')" 'apply plan show '
eq "B11 the sourced kr_tf has exactly one terraform call and sends BOTH streams to files (the chokepoint this script relies on)" "$(code_only "$SIB" | grep -Ec '(^|[^_a-zA-Z-])terraform +\"\$@\"')|$(fn_text kr_tf "$SIB" | grep -c '> "$KR_TMP/tf-${name}.out" 2> "$KR_TMP/tf-${name}.err"')" '1|1'
eq "B12 no Terraform stream file is ever printed: no cat/head/tail/tee/printf/echo/sed/grep of a tf-*.out|err" "$(code_only "$BODY" | grep -Ec '(cat|head|tail|tee|printf|echo|sed|grep|less|more)[^|;]*tf-[a-z0-9${}_-]*\.(out|err)')" '0'
eq "B13 every doppler secrets get is the exact value-silent form (| sha256sum | cut -c1-64) and there is exactly one" "$(code_only "$BODY" | grep -c 'doppler secrets get')|$(code_only "$BODY" | grep -c 'doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null | sha256sum | cut -c1-64)')" '1|1'
# gate table
GATE_ROWS="$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s\n" "${KR_GATE_TABLE[@]}"' _ "$BODY")"
eq "B14 the gate table has 15 rows: per key 1 phase-A row (random_id) plus 1 phase-B row per copy (kb_drift has 2 copies)" "$(wc -l <<<"$GATE_ROWS" | tr -d ' ')|$(grep -c '^A|' <<<"$GATE_ROWS")|$(grep -c '^B|' <<<"$GATE_ROWS")" '15|7|8'
ROWS_OK=0
for k in $KEYS; do
  n="$(grep -c "^[AB]|$k|" <<<"$GATE_ROWS")"; want=$ROWS_OTHER; [[ "$k" == kb_drift_ingest_signing_key ]] && want=$ROWS_KB
  [[ "$n" == "$want" ]] || { ROWS_OK=1; bad "B15 key $k has $n gate rows, want $want (literal)"; }
done
[[ "$ROWS_OK" == 0 ]] && ok "B15 the expected row count per key is pinned from literals: 3 for kb_drift_ingest_signing_key, 2 for every other key"
BAD_FLAG="$(while IFS='|' read -r ph key addr flag acts; do
  case "$ph:$addr" in A:random_id.*) [[ "$flag|$acts" == "replace|delete,create" ]] || echo "bad-A:$addr" ;; B:doppler_secret.*)
    if grep -qw -- "$addr" <<<"$IGNORE_SET"; then [[ "$flag|$acts" == "replace|delete,create" ]] || echo "bad-ign:$addr"; else [[ "$flag|$acts" == "target|update" ]] || echo "bad-upd:$addr"; fi ;; *) echo "bad-shape:$addr" ;; esac
done <<<"$GATE_ROWS")"
eq "B16 the ignore_changes keys are replace-both (delete,create); the others update in place (target|update) - the IGNORE_SET literal is the oracle, Guard 5 derives it from the HCL" "$BAD_FLAG" ""
eq "B17 the copies table in the script equals the literal key|project|config|name table" "$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s\n" "${KK_COPIES[@]}"' _ "$BODY" | cut -d'|' -f1-4)" "$COPIES_LIT"
eq "B18 the -target and -replace flags are each built in exactly one place (the sourced kr_gate_targets / kr_gate_replaces; none in the script)" "$(code_only "$BODY" | grep -c -- '-target=')|$(code_only "$BODY" | grep -c -- "-replace=")" '0|1'
eq "B19 no resource address literal outside the table and the copies table (random_id., doppler_secret., hcloud_, terraform_data.)" "$(code_only "$BODY" | grep -v "^  '[AB]|" | grep -v "^  '[a-z_]*|soleur|" | grep -Ec '(random_id|doppler_secret|hcloud_[a-z]+|terraform_data|tls_[a-z]+)\.[a-z_]+')" '0'
# projection field list
PROJ_KEYS="$(code_only "$BODY" | sed -n "/^KK_PROJECT_JQ=/,/}]'\$/p" | grep -oE '\{address.*\}\]' | grep -oE '[a-z_]+:' | tr -d ':' | tr '\n' ' ' | sed 's/ $//')"
eq "B20 the plan projection keeps exactly these five fields (the full plan JSON holds every root variable and the prior state)" "$PROJ_KEYS" "$PROJECTED_FIELDS"
# tokens
PRINTED="$(env -i PATH=/usr/bin:/bin bash "$BODY" --print-contract 2>&1)"
eq "B21 --print-contract prints the key-rotate header" "$(head -1 <<<"$PRINTED")" 'key-rotate verdict-tokens'
eq "B22 the printed token set equals the literal 35 (set equality, no duplicates)" "$(tail -n +2 <<<"$PRINTED" | sort | tr '\n' ' ')|$(tail -n +2 <<<"$PRINTED" | sort | uniq -d | wc -l | tr -d ' ')" "$(tr ' ' '\n' <<<"$TOKENS" | sort | tr '\n' ' ')|0"
eq "B22b there are exactly 35 tokens" "$(wc -w <<<"$TOKENS" | tr -d ' ')" '35'
EMITTED="$(code_only "$BODY" | grep -oE '(kr_refuse|kr_ok|kr_post_write_failure|kk_redeploy_refuse|KR_CHECK_TOKEN=|tok=)[ "]*[a-z][a-z0-9]*(_[a-z0-9]+)+' | awk '{print $NF}' | sed -E 's/^(KR_CHECK_TOKEN=|tok=)//' | tr -d '"' | sort -u)"
UNLISTED="$(comm -13 <(tr ' ' '\n' <<<"$TOKENS" | sort) <(grep -E '^[a-z]' <<<"$EMITTED" | sort) | grep -vxE 'rotate_ok|reason|kr_ok|kr_refuse' | tr '\n' ' ')"
eq "B23 every verdict literal the script emits is in the list" "$UNLISTED" ""
CODE_NOW="$(code_only "$BODY")"
NEVER="$(for t in $TOKENS; do grep -qw -- "$t" <<<"$CODE_NOW" || grep -qw -- "$t" <<<"$TOKENS_SOURCED_ONLY" || printf '%s ' "$t"; done)"
eq "B24 every listed token has an emitting literal in the script or sits on the literal sourced-only exemption list (rerun_refused, quiet_window_missing, credential_absent)" "$NEVER" ""
# overrides: defined once, at top level
OV_BAD=""; for f in $OVERRIDES kr_out; do [[ "$(grep -c "^${f}() {" "$BODY")" == 1 ]] || OV_BAD="$OV_BAD $f"; done
eq "B25 each of the 11 same-name redefinitions (and the kr_out allowlist) is defined exactly once at top level" "$OV_BAD" ""
# leaked text
eq "B26 the script's code names no converge command: the only 'converge' word in code is the function name kr_converge_cmd" "$(code_only "$BODY" | grep -ci 'converge')|$(code_only "$BODY" | grep -c 'kr_converge_cmd')" "$(code_only "$BODY" | grep -c 'kr_converge_cmd')|$(code_only "$BODY" | grep -c 'kr_converge_cmd')"
eq "B26b inngest-key-rotate appears in code only as the sourced path and as an in-flight workflow name" "$(code_only "$BODY" | grep -c 'inngest-key-rotate')" "$(code_only "$BODY" | grep 'inngest-key-rotate' | grep -c 'scripts/inngest-key-rotate.sh\|KR_INFLIGHT_WORKFLOWS\|sourced')"
# sha256 over the sourced bodies the script calls (by function range, not declare -f): a semantic change forces a deliberate update
PIN_TXT=""; for f in $SOURCED_CALLED; do PIN_TXT+="$(fn_text "$f" "$SIB")"$'\n'; done
PIN_TXT+="$(grep '^KR_EMPTY_SHA=' "$SIB")"$'\n'
PIN_NOW="$(printf '%s' "$PIN_TXT" | SHA256_OF)"
eq "B27 sha256 of the sourced function bodies this script calls (and their transitive callees) equals the pinned value" "$PIN_NOW" "$SOURCED_PIN"
eq "B27b the sourced temp prefix (CTO F1) is still inngest-key-rotate.XXXXXX inside kr_init" "$(fn_text kr_init "$SIB" | grep -c 'inngest-key-rotate.XXXXXX')" '1'
eq "B27c every sourced function listed for the pin was found (no empty range)" "$(for f in $SOURCED_CALLED; do fn_range "$SIB" "$f" | grep -c . ; done | sort | uniq -c | tr -s ' ' | tr '\n' ';')" " $(wc -w <<<"$SOURCED_CALLED" | tr -d ' ') 1;"
# in-flight list and the workflows it names exist
INF="$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s\n" "${KR_INFLIGHT_WORKFLOWS[@]}"' _ "$BODY")"
eq "B28 the in-flight list is exactly the seven related workflows (key-rotate.yml is NOT in it: the sourced helper counts later runs too)" "$(sort <<<"$INF" | tr '\n' ' ')" "apply-deploy-pipeline-fix.yml apply-web-platform-infra.yml cutover-inngest.yml deploy-inngest-image.yml inngest-key-rotate.yml inngest-link-flip.yml web-platform-release.yml "
MISSING_WF=""; for w in $INF kb-drift-walker.yml; do [[ -f "$REPO_ROOT/.github/workflows/$w" ]] || MISSING_WF="$MISSING_WF $w"; done
eq "B29 every workflow the in-flight list and the walker rung name exists under .github/workflows (a rename would be a permanent run_list_unreadable)" "$MISSING_WF" ""
eq "B30 the committed owner allowlist is the CODEOWNERS owner, exactly" "$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s" "${KK_OWNER_LOGINS[*]}"' _ "$BODY")|$(grep -E '^\*[[:space:]]+@' "$REPO_ROOT/.github/CODEOWNERS" | awk '{print $2}' | tr -d '@')" "$OWNER_LOGIN|$OWNER_LOGIN"
# budgets (seconds) -> the workflow timeouts above are literals; the script's table must agree
BUD="$(env -i PATH="$PATH" bash -c 'source "$1"; echo "$KR_GUARD_S $KR_GUARD_JOB_S $KK_APPLY_STEP_S $KK_APPLY_JOB_S $KR_REDEPLOY_STEP_S $KR_REDEPLOY_JOB_S $KR_NOTIFY_S $KR_NOTIFY_JOB_S"' _ "$BODY")"
eq "B31 the script's budget table in minutes equals the literal workflow timeouts (guard 15/25, apply 40/50, redeploy 85/95, notify 5/15)" "$(for s in $BUD; do echo $(( (s + 59) / 60 )); done | tr '\n' ' ')" "$MIN_GUARD_STEP $MIN_GUARD_JOB $MIN_APPLY_STEP $MIN_APPLY_JOB $MIN_REDEPLOY_STEP $MIN_REDEPLOY_JOB $MIN_NOTIFY_STEP $MIN_NOTIFY_JOB "
eq "B32 no test seam (KR_*, KK_*) is set anywhere in the workflow's code (comments may name the budget table)" "$(grep -v '^ *#' "$WF" | grep -cE '\bK[RK]_[A-Z_]+')" '0'
eq "B33 the Terraform plan variables come only from the loader and doppler run: the workflow sets no TF_VAR and no TF_LOG" "$(grep -cE 'TF_VAR_|TF_LOG' "$WF")" '0'

printf '\n=== C0. --print-contract: offline, credential-free, fast ===\n'
T0=$SECONDS
PC_OUT="$(env -i PATH=/usr/bin:/bin bash "$BODY" --print-contract 2>&1)"; PC_RC=$?
eq "C0.1 --print-contract exits 0 under an empty environment, prints the header and 35 snake_case tokens, one per line, within 15 s" "$PC_RC|$(tail -n +2 <<<"$PC_OUT" | grep -Ec '^[a-z][a-z0-9]*(_[a-z0-9]+)+$')|$(( SECONDS - T0 < 15 ? 1 : 0 ))" '0|35|1'

# ---------------------------------------------------------------------------------------------------------------------------
printf '\n=== C. behaviour against stubs: the world ===\n'
at() { date -u -d "2026-11-02 $1" +%s; }       # at HH:MM:SS -> epoch (the single fake clock)
NOW0="$(at 12:00:00)"
TODAY="$(date -u -d "@$NOW0" +%F)"
UPPER() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
triple_of() { # key index(1-based) -> "project config name"
  grep "^$1|" <<<"$COPIES_LIT" | sed -n "${2:-1}p" | awk -F'|' '{print $2, $3, $4}'
}

# make_world <dir>: a hermetic fake world (PATH shims + a state directory the shims read). Built ONCE and cp -a'd per scenario.
make_world() {
  local d="$1" k p c n
  assert_fixture_dir "$d"
  mkdir -p "$d/bin" "$d/state" "$d/infra" "$d/rt"
  printf '%s\n' "$NOW0" > "$d/state/now"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$S_B64" "$S_HEX" "$S_SIGN" "$(printf 'x' | SHA256_OF)" "$S_STD" "$S_TOKV" > "$d/state/sent"
  while IFS='|' read -r k p c n; do
    printf '%s' "${OLD_PFX}-${p}-${c}-${n}" > "$d/state/copy_${p}_${c}_${n}"
  done <<<"$COPIES_LIT"
  printf '[{"name":"action-required"},{"name":"owner_step_pending"}]' > "$d/state/labels.json"
  cat > "$d/bin/adv" <<'SH'
#!/usr/bin/env bash
echo "sleep $1" >> "$STUB/sleep.log"
s="$(cat "$STUB/state/now")"; echo $((s + ${1:-5})) > "$STUB/state/now"
SH
  cat > "$d/bin/doppler" <<'SH'
#!/usr/bin/env bash
# STRICT: every modelled call is matched on its WHOLE argv (verb, name, -p project, -c config) and on the token class of the call
# (the copy reads carry the Terraform token). Anything else is refused with exit 64 and logged to refusals.log, which the suite
# requires to be empty for every non-mutant scenario.
echo "doppler $*" >> "$STUB/doppler.log"
refuse() { echo "doppler REFUSED: $*" >> "$STUB/refusals.log"; exit 64; }
if [[ "$1" == run ]]; then
  [[ "$*" == "run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- "* ]] || refuse "$@"
  shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift
  exec "$@"
fi
[[ "${DOPPLER_TOKEN:-}" == dp.tffixture ]] || refuse "copy call with token class '${DOPPLER_TOKEN:-}': $*"
S="$STUB/state"
if [[ "$1 $2" == "secrets --only-names" ]]; then
  [[ "$3" == -p && "$5" == -c && $# == 6 ]] || refuse "$@"
  p="$4"; c="$6"
  [[ -f "$S/names_rc_${p}_${c}" ]] && exit "$(cat "$S/names_rc_${p}_${c}")"
  [[ -f "$S/names_empty_${p}_${c}" ]] && exit 0
  # the real table format (borders, one NAME column)
  printf '┌──────────────────────────────────┐\n│ NAME                             │\n├──────────────────────────────────┤\n│ OTHER_SECRET                     │\n'
  for f in "$S"/copy_${p}_${c}_*; do [[ -f "$f" ]] || continue; nm="${f##*/copy_${p}_${c}_}"; printf '│ %-32s │\n' "$nm"; done
  printf '└──────────────────────────────────┘\n'
  exit 0
fi
[[ "$1" == secrets && "$2" == get && "$4" == --plain && "$5" == -p && "$7" == -c && $# == 8 ]] || refuse "$@"
nm="$3"; p="$6"; c="$8"; f="$S/copy_${p}_${c}_${nm}"
[[ -f "$S/get_junk_fail_${p}_${c}_${nm}" ]] && { echo "Error: boom"; exit 1; }
[[ -f "$S/get_empty_${p}_${c}_${nm}" ]] && exit 0
[[ -f "$S/get_rc_${p}_${c}_${nm}" ]] && exit "$(cat "$S/get_rc_${p}_${c}_${nm}")"
[[ -f "$f" ]] || exit 1
if [[ -f "$S/lag_${p}_${c}_${nm}" ]]; then # read-after-write lag: the old value for the first N reads
  n="$(cat "$S/lag_${p}_${c}_${nm}")"
  if [[ "$n" -gt 0 ]]; then echo $((n - 1)) > "$S/lag_${p}_${c}_${nm}"; cat "$S/old_${p}_${c}_${nm}"; exit 0; fi
fi
cat "$f"
SH
  cat > "$d/bin/terraform" <<'SH'
#!/usr/bin/env bash
# A stub with real fidelity: plan actions are DERIVED from argv (-target/-replace) and from a LITERAL ignore_changes set (the four inngest_* secrets).
S="$STUB/state"
echo "terraform $1 TFLOG=${TF_LOG:-unset} TFLOGPATH=${TF_LOG_PATH:-unset}" >> "$STUB/tf.log"
{ read -r B64; read -r HEX; read -r SIGN; read -r SHA; read -r STD; read -r TOKV; } < "$S/sent"
sentinels() { # key-shaped strings on BOTH streams, as the real tool prints them
  printf 'random_id.x: Creation complete after 0s [id=%s]\n  hex = "%s"\n  value = "%s"\n  sha = "%s"\n  std = "%s"\n  var = "%s"\n' "$B64" "$HEX" "$SIGN" "$SHA" "$STD" "$TOKV"
  printf 'Error: refresh [id=%s] hex=%s %s %s %s %s\n' "$B64" "$HEX" "$SIGN" "$SHA" "$STD" "$TOKV" >&2
}
[[ -n "${TF_LOG_PATH:-}" ]] && printf 'TRACE [id=%s]\n' "$B64" > "$TF_LOG_PATH"
[[ -n "${TF_LOG:-}" ]] && printf 'TRACE value=%s\n' "$SIGN" >&2
rcf() { [[ -f "$S/$1" ]] && cat "$S/$1" || echo 0; }
IGN="doppler_secret.inngest_manual_trigger_secret_dev doppler_secret.inngest_manual_trigger_secret_prd doppler_secret.inngest_signing_key_dev doppler_secret.inngest_event_key_dev"
parent_of() { case "$1" in
  doppler_secret.kb_drift_ingest_signing_key|doppler_secret.kb_drift_ingest_signing_key_app_runtime) echo random_id.kb_drift_ingest_signing_key ;;
  doppler_secret.github_app_webhook_secret) echo random_id.github_webhook_secret ;;
  doppler_secret.*) echo "random_id.${1#doppler_secret.}" ;;
esac; }
copy_of() { case "$1" in # address -> project_config_name (the file stem)
  doppler_secret.inngest_manual_trigger_secret_dev) echo soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET ;;
  doppler_secret.inngest_manual_trigger_secret_prd) echo soleur_prd_INNGEST_MANUAL_TRIGGER_SECRET ;;
  doppler_secret.inngest_signing_key_dev) echo soleur_dev_INNGEST_SIGNING_KEY ;;
  doppler_secret.inngest_event_key_dev) echo soleur_dev_INNGEST_EVENT_KEY ;;
  doppler_secret.kb_drift_ingest_signing_key) echo soleur_prd_kb_drift_walker_KB_DRIFT_INGEST_SIGNING_KEY ;;
  doppler_secret.kb_drift_ingest_signing_key_app_runtime) echo soleur_prd_KB_DRIFT_INGEST_SIGNING_KEY ;;
  doppler_secret.egress_audit_ingest_token) echo soleur_prd_EGRESS_AUDIT_INGEST_TOKEN ;;
  doppler_secret.github_app_webhook_secret) echo soleur_prd_GITHUB_APP_WEBHOOK_SECRET ;;
esac; }
sub="$1"; shift
case "$sub" in
  init) sentinels; exit "$(rcf init_rc)" ;;
  plan)
    out=""; : > "$STUB/last_def"
    for a in "$@"; do
      case "$a" in
        -out=*) out="${a#-out=}" ;;
        -target=*) echo "T ${a#-target=}" >> "$STUB/last_def" ;;
        -replace=*) echo "R ${a#-replace=}" >> "$STUB/last_def" ;;
      esac
    done
    cp "$STUB/last_def" "$out"
    [[ -f "$S/plan_adv" ]] && "$STUB/bin/adv" "$(cat "$S/plan_adv")"
    echo "plan $(tr '\n' ' ' < "$out")" >> "$STUB/tf.log"
    sentinels; exit "$(rcf plan_rc)" ;;
  show)
    def="${@: -1}"
    if [[ -f "$S/show_raw" ]]; then cat "$S/show_raw"; echo "[id=$B64]" >&2; exit "$(rcf show_rc)"; fi
    entries=("$(jq -cn --arg id "$B64" '{address:"doppler_project.inngest",mode:"managed",type:"doppler_project",name:"inngest",change:{actions:["no-op"],before:{id:$id},after:{id:$id},after_unknown:{}}}')")
    while read -r kind addr; do
      [[ -n "$addr" ]] || continue
      if [[ "$kind" == T ]] && grep -q "^R $addr\$" "$def"; then continue; fi
      reason=""; unknown=true; bnull=false
      case "$addr" in
        random_id.*)
          if [[ -f "$S/state_absent_$addr" ]]; then acts='["create"]'; bnull=true
          elif grep -q "^R $addr\$" "$def"; then acts='["delete","create"]'; reason=replace_by_request; [[ -f "$S/tainted_$addr" ]] && reason=replace_because_tainted
          else acts='["no-op"]'; fi ;;
        doppler_secret.*)
          par="$(parent_of "$addr")"; stem="$(copy_of "$addr")"
          if [[ ! -f "$S/copy_$stem" ]]; then acts='["create"]'; bnull=true
          elif grep -q "^R $addr\$" "$def"; then acts='["delete","create"]'; reason=replace_by_request; [[ -f "$S/tainted_$addr" ]] && reason=replace_because_tainted
          elif grep -q "^R $par\$" "$def"; then if grep -qw -- "$addr" <<<"$IGN"; then acts='["no-op"]'; else acts='["update"]'; fi
          else acts='["no-op"]'; fi ;;
        *) acts='["update"]' ;;
      esac
      [[ -f "$S/nounknown_$addr" ]] && unknown=false
      [[ -f "$S/actions_$addr" ]] && { acts="$(cat "$S/actions_$addr")"; [[ "$acts" == '["create"]' ]] && bnull=true; }
      [[ -f "$S/nonnullbefore_$addr" ]] && bnull=false
      entries+=("$(jq -cn --arg a "$addr" --argjson acts "$acts" --arg r "$reason" --argjson bn "$bnull" --argjson unk "$unknown" --arg id "$B64" --arg hex "$HEX" --arg std "$STD" \
        '{address:$a,mode:"managed",type:($a|split(".")[0]),name:($a|split(".")[1]),change:{actions:$acts,before:(if $bn then null else {id:$id,hex:$hex,b64_url:$id,b64_std:$std,value:("signkey-test-"+$hex)} end),after:{id:$id},after_unknown:{id:true,hex:true,b64_url:true,b64_std:true,value:$unk}}} + (if $r != "" then {action_reason:$r} else {} end)')")
    done < <(sort -u "$def")
    for f in "$S"/drop_*; do [[ -f "$f" ]] || continue; a="${f##*/drop_}"; mapfile -t entries < <(printf '%s\n' "${entries[@]}" | jq -c --arg a "$a" 'select(.address != $a)'); done
    for f in "$S"/dup_*; do [[ -f "$f" ]] || continue; a="${f##*/dup_}"; entries+=("$(printf '%s\n' "${entries[@]}" | jq -c --arg a "$a" 'select(.address == $a)' | head -1)"); done
    [[ -f "$S/reverse" ]] && mapfile -t entries < <(printf '%s\n' "${entries[@]}" | tac)
    extra='[]'; [[ -f "$S/plan_extra" ]] && extra="$(cat "$S/plan_extra")"
    printf '%s\n' "${entries[@]}" | jq -cs --argjson extra "$extra" --arg tok "$TOKV" --arg id "$B64" --arg hex "$HEX" \
      '{format_version:"1.2",terraform_version:"1.10.5",variables:{doppler_token_workplace:{value:$tok}},prior_state:{values:{root_module:{resources:[{address:"random_id.prior",values:{id:$id,hex:$hex}}]}}},resource_changes:(. + $extra)}'
    echo "refresh [id=$B64]" >&2
    exit "$(rcf show_rc)" ;;
  apply)
    def="${@: -1}"
    n=$(( $(cat "$S/applyn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/applyn"
    echo "apply" >> "$STUB/tf.log"
    # observation INSIDE the window: had the gate (the projection file) and the last re-checks run before the write?
    echo "obs proj=$(ls "$STUB"/rt/inngest-key-rotate.*/proj-p.json 2>/dev/null | wc -l | tr -d ' ') ghcalls=$(wc -l < "$STUB/gh.log" 2>/dev/null || echo 0)" >> "$STUB/apply_obs.log"
    sentinels
    if [[ -f "$S/apply_deletes" ]]; then # the destroy half of a -replace ran, the create did not
      for a in $(grep '^R doppler_secret' "$def" | cut -d' ' -f2); do rm -f "$S/copy_$(copy_of "$a")"; done
      exit 1
    fi
    if [[ ! -f "$S/apply_noeffect" ]]; then
      newv="new${n}$(printf 'e%.0s' {1..40})"
      while read -r kind addr; do
        [[ "$kind" == R && "$addr" == random_id.* ]] || continue
        for a in $(grep '^[TR] doppler_secret' "$def" | cut -d' ' -f2 | sort -u); do
          [[ "$(parent_of "$a")" == "$addr" ]] || continue
          stem="$(copy_of "$a")"
          # an ignore_changes secret changes only when it is itself replaced; the others follow the replaced random_id
          if grep -qw -- "$a" <<<"$IGN" && ! grep -q "^R $a\$" "$def"; then continue; fi
          [[ -f "$S/apply_skip_$a" ]] && continue
          old="$(cat "$S/copy_$stem" 2>/dev/null)"
          v="$newv"; [[ -f "$S/apply_diverge_$a" ]] && v="${newv}d"
          printf '%s' "$v" > "$S/copy_$stem"
          if [[ -f "$S/lag_reads" ]]; then printf '%s' "$old" > "$S/old_$stem"; cp "$S/lag_reads" "$S/lag_$stem"; fi
        done
      done < "$def"
    fi
    for f in "$S"/apply_dropcopy_*; do [[ -f "$f" ]] || continue; rm -f "$S/copy_$(copy_of "${f##*/apply_dropcopy_}")"; done
    [[ -f "$S/post_get_fail" ]] && for a in $(grep '^[TR] doppler_secret' "$def" | cut -d' ' -f2 | sort -u); do echo 1 > "$S/get_rc_$(copy_of "$a")"; done
    exit "$(rcf apply_rc)" ;;
  *) exit 64 ;;
esac
SH
  cat > "$d/bin/ssh-keygen" <<'SH'
#!/usr/bin/env bash
f=""; while [[ $# -gt 0 ]]; do [[ "$1" == -f ]] && f="$2"; shift; done
: > "$f"; : > "$f.pub"
SH
  cat > "$d/bin/gh" <<'SH'
#!/usr/bin/env bash
# STRICT: --repo, the workflow, the status, the label and the json fields of every modelled call are matched; anything else is refused
# with exit 64 and logged to refusals.log (required empty for every non-mutant scenario).
echo "gh $*" >> "$STUB/gh.log"
S="$STUB/state"
refuse() { echo "gh REFUSED: $*" >> "$STUB/refusals.log"; exit 64; }
arg_after() { local k="$1" prev=""; shift; for a in "$@"; do [[ "$prev" == "$k" ]] && { printf '%s' "$a"; return 0; }; prev="$a"; done; return 1; }
[[ "$(arg_after --repo "$@")" == acme/repo ]] || refuse "$@"
case "$1 $2" in
  "run list")
    [[ -f "$S/runlist_rc" ]] && exit "$(cat "$S/runlist_rc")"
    wf="$(arg_after --workflow "$@")"; st="$(arg_after --status "$@")"
    [[ "$(arg_after --json "$@")" == databaseId && "$(arg_after --limit "$@")" == 50 ]] || refuse "$@"
    case "$wf" in apply-web-platform-infra.yml|apply-deploy-pipeline-fix.yml|web-platform-release.yml|inngest-key-rotate.yml|inngest-link-flip.yml|cutover-inngest.yml|deploy-inngest-image.yml|key-rotate.yml|kb-drift-walker.yml) ;; *) refuse "$@" ;; esac
    case "$st" in in_progress|queued|waiting|pending|requested) ;; *) refuse "$@" ;; esac
    [[ -f "$S/runlist_rc_$wf" ]] && exit "$(cat "$S/runlist_rc_$wf")"
    cf="$S/calls_${wf}_${st}"; c=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$cf"
    if [[ -f "$S/late_after_${wf}_${st}" && "$c" -gt "$(cat "$S/late_after_${wf}_${st}")" ]]; then echo '[{"databaseId":777}]'; exit 0; fi
    cat "$S/runs_${wf}_${st}.json" 2>/dev/null || echo '[]' ;;
  "label list")
    [[ "$(arg_after --json "$@")" == name && "$(arg_after --limit "$@")" == 1000 ]] || refuse "$@"
    [[ -f "$S/label_list_rc" ]] && exit "$(cat "$S/label_list_rc")"
    cat "$S/labels.json" ;;
  "issue list")
    lab="$(arg_after --label "$@")"; [[ "$(arg_after --state "$@")" == open && "$(arg_after --limit "$@")" == 1000 ]] || refuse "$@"
    [[ -f "$S/issue_list_rc" ]] && exit "$(cat "$S/issue_list_rc")"
    case "$lab" in
      action-required) [[ "$(arg_after --json "$@")" == number,title ]] || refuse "$@"; cat "$S/issues.json" 2>/dev/null || echo '[]' ;;
      owner_step_pending) [[ "$(arg_after --json "$@")" == title ]] || refuse "$@"; cat "$S/issues_owner.json" 2>/dev/null || echo '[]' ;;
      *) refuse "$@" ;;
    esac ;;
  "issue create")
    t="$(arg_after --title "$@")"; bf="$(arg_after --body-file "$@")"
    labs=""; prev=""; for a in "$@"; do [[ "$prev" == --label ]] && labs="$labs $a"; prev="$a"; done
    for l in $labs; do grep -q "\"$l\"" "$S/labels.json" || { echo "could not add label: '$l' not found" >&2; exit 1; }; done
    n=$(( $(cat "$S/issuen" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/issuen"
    echo "$t | labels:$labs" >> "$STUB/issues_created.log"; cp "$bf" "$STUB/issue_body_$n.md"
    if [[ ! -f "$S/create_vanishes" ]]; then
      jq -c --arg t "$t" --argjson n "$((100 + n))" '. + [{number:$n,title:$t}]' "$S/issues.json" 2>/dev/null > "$S/issues.tmp" || jq -cn --arg t "$t" --argjson n "$((100 + n))" '[{number:$n,title:$t}]' > "$S/issues.tmp"
      mv "$S/issues.tmp" "$S/issues.json"
    fi
    echo "https://github.example/acme/repo/issues/$((100 + n))" ;;
  "issue comment") [[ "$3" =~ ^[0-9]+$ ]] || refuse "$@"; cp "$(arg_after --body-file "$@")" "$STUB/comment_body_$3.md"; echo "$3" >> "$STUB/issues_commented.log" ;;
  "issue close") [[ "$3" =~ ^[0-9]+$ ]] || refuse "$@"; echo "$3" >> "$STUB/issues_closed.log" ;;
  *) refuse "$@" ;;
esac
exit 0
SH
  cat > "$d/bin/track.sh" <<'SH'
#!/usr/bin/env bash
echo "track WEB_HOST_PRIVATE_IPS=${WEB_HOST_PRIVATE_IPS:-} REDEPLOY_TIMEOUT_S=${REDEPLOY_TIMEOUT_S:-} GH_TOKEN=${GH_TOKEN:+set}" >> "$STUB/track.log"
echo "dispatch-web-redeploy: stub verdict"
exit "$(cat "$STUB/state/track_rc" 2>/dev/null || echo 0)"
SH
  chmod +x "$d"/bin/*
}
WORLD0="$TMP/world0"; make_world "$WORLD0"

# mk_tree <dir> [mutated-script-source] [mutated-sibling-source]: a repo-shaped tree of SYMLINKS (scripts/ is ~18 MB; never copied) whose two
# script files are the real ones or mutated COPIES. tests/scripts/test-tf-redact-random-ids.sh is a STUB suite (the real one belongs to
# PR-F): it prints the three labelled [ok] rows and exits 0.
mk_tree() {
  local t="$1" e
  assert_fixture_dir "$t"
  mkdir -p "$t/scripts" "$t/tests/scripts"
  for e in "$REPO_ROOT"/scripts/* "$REPO_ROOT"/scripts/.[!.]*; do [[ -e "$e" ]] || continue; case "${e##*/}" in key-rotate.sh|inngest-key-rotate.sh) ;; *) ln -s "$e" "$t/scripts/${e##*/}" ;; esac; done
  if [[ -n "${2:-}" ]]; then cp "$2" "$t/scripts/key-rotate.sh"; else ln -s "$BODY" "$t/scripts/key-rotate.sh"; fi
  if [[ -n "${3:-}" ]]; then cp "$3" "$t/scripts/inngest-key-rotate.sh"; else ln -s "$SIB" "$t/scripts/inngest-key-rotate.sh"; fi
  ln -s "$REPO_ROOT/.github" "$t/.github"; ln -s "$REPO_ROOT/apps" "$t/apps"
  printf '#!/usr/bin/env bash\nprintf "[ok] tainted-must-be-replaced block redacted\\n[ok] deposed-will-be-destroyed block redacted\\n[ok] drift-has-changed block redacted\\n[ok] another row\\n"\nexit 0\n' > "$t/tests/scripts/test-tf-redact-random-ids.sh"
}
RT_REAL="$TMP/rt-real"; mk_tree "$RT_REAL"
RT="$RT_REAL"
D=""
fresh() { D="$(mktemp -u "$TMP/s.XXXXXX")"; cp -a "$WORLD0" "$D"; }

# base environments
G_COMMON=(GH_TOKEN=ghs_fixture)
g_plan() { printf '%s\n' "${G_COMMON[@]}" INPUT_MODE=plan "INPUT_KEY=$1" INPUT_CONFIRM= INPUT_QUIET_WINDOW=false INPUT_WEBHOOK_PATCH_READY=false "${@:2}"; }
g_rotate() { printf '%s\n' "${G_COMMON[@]}" INPUT_MODE=rotate "INPUT_KEY=$1" "INPUT_CONFIRM=ROTATE-$(UPPER "$1")-$TODAY" INPUT_QUIET_WINDOW=true INPUT_WEBHOOK_PATCH_READY=true "${@:2}"; }
a_env() { # mode key -> the apply job's environment
  printf '%s\n' AWS_ACCESS_KEY_ID=AKIAfixture AWS_SECRET_ACCESS_KEY=secretfixture DOPPLER_TOKEN=dp.fixture DOPPLER_TOKEN_TF=dp.tffixture GH_TOKEN=ghs_fixture "EFF_MODE=$1" "EFF_KEY=$2" "EFF_GUARD_EPOCH=$NOW0" "${@:3}"
}

STREAMS="$TMP/all-streams.txt"; : > "$STREAMS"
SCAN_ASSERT=1; : > "$TMP/runs.cnt"; : > "$TMP/scans.cnt"; : > "$TMP/leaks.log"
LEAK_RE="$S_HEX|$S_B64|signkey-(prod|test)-[A-Za-z0-9_-]{8,}|\[id=[A-Za-z0-9_-]{20,}\]|[0-9a-f]{64}|[A-Za-z0-9_-]{43}|$(printf '%s' "$S_STD" | sed 's/[+/]/./g')|$S_TOKV"
# scan_streams: every stream a run can publish (stdout+stderr, step summary, job outputs, the issue body copies, the annotations
# inside OUT, the argv logs) and the temp tree left after exit. The only long snake_case word, the egress verdict token, is neutralized
# first (it is a fixed vocabulary token, not key material, and is longer than 43 characters).
scan_streams() {
  local txt hits
  echo x >> "$TMP/scans.cnt"
  txt="$ALL"$'\n'"$(cat "$D"/gh.log "$D"/doppler.log "$D"/tf.log "$D"/track.log "$D"/issue_body_*.md "$D"/comment_body_*.md 2>/dev/null)"
  txt="${txt//egress_rotate_unsupported_no_vector_restart_lever/EGRESS}"
  hits="$(grep -Ec "$LEAK_RE" <<<"$txt" || true)"
  LAST_HITS="$hits"
  if [[ "$hits" != 0 && "$SCAN_ASSERT" == 1 ]]; then echo "'$LAST_LABEL' $(grep -Eo "$LEAK_RE" <<<"$txt" | head -2 | cut -c1-6 | tr '\n' ' ')" >> "$TMP/leaks.log"; fi
  printf '%s\n' "$txt" >> "$STREAMS"
}
LAST_LABEL=""
# run_script <subcommand words> [VAR=val ...] (uses $D, $RT): sets OUT (stdout+stderr), RC, ALL (OUT plus job outputs and summary)
run_script() {
  local sub="$1"; shift
  echo x >> "$TMP/runs.cnt"; LAST_LABEL="$sub"
  : > "$D/gh_output"; : > "$D/summary"
  # shellcheck disable=SC2086
  OUT="$(env -i PATH="$D/bin:$PATH" HOME="$D" STUB="$D" TMPDIR="$D/rt" RUNNER_TEMP="$D/rt" \
    KR_NOW="cat $D/state/now" KR_SLEEP="$D/bin/adv" KR_TRACK="$D/bin/track.sh" KR_INFRA_DIR="$D/infra" \
    GITHUB_OUTPUT="$D/gh_output" GITHUB_STEP_SUMMARY="$D/summary" GITHUB_RUN_ID=9001 GITHUB_RUN_ATTEMPT=1 GITHUB_REF=refs/heads/main \
    GITHUB_ACTOR="$OWNER_LOGIN" GITHUB_TRIGGERING_ACTOR="$OWNER_LOGIN" GITHUB_REPOSITORY=acme/repo GITHUB_SERVER_URL=https://github.example \
    "$@" bash "$RT/scripts/key-rotate.sh" $sub 2>&1)"; RC=$?
  ALL="$OUT"$'\n'"$(cat "$D/gh_output" "$D/summary" 2>/dev/null)"
  scan_streams
}
run_g() { local sub="$1"; shift; mapfile -t _e < <("$@"); run_script "$sub" "${_e[@]}"; }   # run_g guard g_rotate key / run_g guard g_plan key
out_of() { grep "^$1=" "$D/gh_output" | tail -1 | cut -d= -f2-; }
verdict_of() { out_of verdict; }
nlog() { [[ -f "$1" ]] || { echo 0; return; }; grep -c "$2" "$1" || true; }
tfapplied() { nlog "$D/tf.log" '^apply$'; }
refusals() { [[ -s "$D/refusals.log" ]] && wc -l < "$D/refusals.log" | tr -d ' ' || echo 0; }
set_state() { printf '%s' "$2" > "$D/state/$1"; }
touch_state() { : > "$D/state/$1"; }
copy_file() { echo "$D/state/copy_$1_$2_$3"; }
copy_val() { cat "$(copy_file "$1" "$2" "$3")" 2>/dev/null; }
sha_of_copy() { copy_val "$1" "$2" "$3" | SHA256_OF; }

[[ "${#S_B64}" == 43 && "${#S_HEX}" == 64 && "${#S_STD}" == 44 ]] && ok "C-fix sentinels have the shape of the real material (43-char base64url id, 64-hex, 44-char standard base64 with + and /, signkey-test-<hex>, a token-shaped variable value)" || bad "C-fix sentinel lengths"

# ---------------------------------------------------------------------------------------------------------------------------
printf '\n=== C1. precondition (the redaction sanity step) ===\n'
fresh; run_script precondition
eq "C1.1 a green redaction suite with the three labelled rows exports redaction_ok=true and prints no verdict token" "$RC|$(out_of redaction_ok)|$(grep -c 'verdict=' <<<"$OUT")" '0|true|0'
fresh; run_script precondition GITHUB_REF=refs/heads/feature
eq "C1.2 off main it refuses ref_refused before running the suite" "$RC|$(verdict_of)|$(out_of redaction_ok)" '1|ref_refused|false'
RT_PRE="$TMP/rt-pre-red"; mk_tree "$RT_PRE"
printf '#!/usr/bin/env bash\nprintf "[ok] tainted-must-be-replaced x\\n[ok] drift-has-changed y\\n"\nexit 0\n' > "$RT_PRE/tests/scripts/test-tf-redact-random-ids.sh"
fresh; RT="$RT_PRE" run_script precondition
eq "C1.3 a suite that lacks the deposed row label (a ref predating the filter fix) refuses redaction_coverage_unconfirmed" "$RC|$(verdict_of)|$(out_of redaction_ok)" '1|redaction_coverage_unconfirmed|false'
printf '#!/usr/bin/env bash\nprintf "[ok] tainted-must-be-replaced x\\n[ok] deposed-will-be-destroyed z\\n[ok] drift-has-changed y\\n[FAIL] other\\n"\nexit 1\n' > "$RT_PRE/tests/scripts/test-tf-redact-random-ids.sh"
fresh; RT="$RT_PRE" run_script precondition
eq "C1.4 a failing suite (non-zero exit) refuses even when every label is present" "$RC|$(verdict_of)" '1|redaction_coverage_unconfirmed'
printf '#!/usr/bin/env bash\nenv | cut -d= -f1 | sort | tr "\\n" " " > "$STUB/pre_env.txt"\nprintf "[ok] tainted-must-be-replaced x\\n[ok] deposed-will-be-destroyed z\\n[ok] drift-has-changed y\\n"\nexit 0\n' > "$RT_PRE/tests/scripts/test-tf-redact-random-ids.sh"
fresh; RT="$RT_PRE" run_script precondition GH_TOKEN=ghs_fixture DOPPLER_TOKEN=dp.fixture
eq "C1.5 the suite runs under env -i PATH HOME LC_ALL: no token reaches it" "$(tr ' ' '\n' < "$D/pre_env.txt" | grep -Ev '^(PATH|HOME|LC_ALL|PWD|SHLVL|_|OLDPWD)$' | tr '\n' ' ')" ''

printf '\n=== C2. guard: the refusal ladder ===\n'
DEVK=inngest_manual_trigger_secret_dev
guard_pass() { [[ "$RC" == 0 && "$(verdict_of)" == guard_ok && "$(out_of go)" == true ]]; }
guard_row() { # id desc token key [VAR=val ...] : a ROTATE guard run that must refuse with <token>, nothing written
  local id="$1" desc="$2" tok="$3" key="$4"; shift 4
  mapfile -t _b < <(g_rotate "$key"); run_script guard "${_b[@]}" "$@"
  if [[ "$RC" != 0 && "$(verdict_of)" == "$tok" && "$(out_of go)" == false && "$(nlog "$D/tf.log" .)" == 0 && "$(refusals)" == 0 ]]; then ok "$id $desc -> verdict=$tok, go=false, nothing written"; else bad "$id $desc" "rc=$RC verdict=$(verdict_of) want=$tok refusals=$(refusals)"; fi
}
fresh; run_g guard g_rotate "$DEVK"
guard_pass && [[ "$(out_of mode)|$(out_of key)|$(out_of run_apply)|$(out_of run_redeploy)|$(out_of guard_epoch)" == "rotate|$DEVK|true|true|$NOW0" ]] && ok "C2.1 a compliant dev-key rotate passes the guard: go=true, apply and redeploy enabled, guard_epoch from the single clock" || bad "C2.1 rc=$RC" "$(cat "$D/gh_output")"
[[ "$(nlog "$D/tf.log" .)" == 0 && "$(nlog "$D/doppler.log" .)" == 0 && "$(refusals)" == 0 ]] && ok "C2.1b the guard calls neither Terraform nor Doppler (it holds no Doppler credential)" || bad "C2.1b guard touched terraform/doppler"
fresh; run_g guard g_plan "$DEVK"
eq "C2.2 plan: no confirm, no quiet_window needed; run_redeploy=false; the boolean report is printed" "$(guard_pass && echo pass)|$(out_of run_apply)|$(out_of run_redeploy)|$(grep -c 'key-rotate check ' <<<"$OUT")" 'pass|true|false|3'
fresh; guard_row C2.3 "GITHUB_REF is not main (and the inputs are ALSO bad: no other rung may print first)" ref_refused "$DEVK" GITHUB_REF=refs/heads/feature INPUT_MODE=apply
[[ "$OUT" != *inputs_invalid* ]] && ok "C2.3b ref_refused is the only verdict printed" || bad "C2.3b another rung printed before ref_refused"
fresh; guard_row C2.4 "mode outside {plan,rotate}" inputs_invalid "$DEVK" INPUT_MODE=apply
fresh; guard_row C2.4b "an empty mode" inputs_invalid "$DEVK" INPUT_MODE=
fresh; guard_row C2.5 "tunnel_secret is not a rotatable key" inputs_invalid "$DEVK" INPUT_KEY=tunnel_secret
fresh; guard_row C2.6 "a bot actor (x[bot])" actor_refused "$DEVK" 'GITHUB_ACTOR=x[bot]'
fresh; guard_row C2.6b "a bot triggering actor" actor_refused "$DEVK" 'GITHUB_TRIGGERING_ACTOR=y[bot]'
fresh; guard_row C2.6c "an empty actor" actor_refused "$DEVK" GITHUB_ACTOR=
fresh; guard_row C2.6d "a login ending in t is NOT a bot (a glob *[bot] would refuse it as actor_refused); it is simply not the owner" actor_not_owner "$DEVK" GITHUB_ACTOR=Scot GITHUB_TRIGGERING_ACTOR=Scot
fresh; guard_row C2.7 "an actor outside the owner allowlist" actor_not_owner "$DEVK" GITHUB_ACTOR=someone GITHUB_TRIGGERING_ACTOR=someone
fresh; guard_row C2.7b "the triggering actor is not the owner although github.actor is" actor_not_owner "$DEVK" GITHUB_TRIGGERING_ACTOR=someone
fresh; guard_row C2.7c "the allowlist is case-sensitive" actor_not_owner "$DEVK" GITHUB_ACTOR=Deruelle GITHUB_TRIGGERING_ACTOR=Deruelle
for a in 2 10 0 ""; do fresh; guard_row C2.8 "GITHUB_RUN_ATTEMPT='$a' (exactly 1; no default, no glob)" rerun_refused "$DEVK" "GITHUB_RUN_ATTEMPT=$a"; done
fresh; guard_row C2.9 "a confirm with the wrong date" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-2001-01-01"
fresh; guard_row C2.9b "a confirm with a trailing suffix (exact compare, not a prefix glob)" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-$TODAY-X"
fresh; guard_row C2.9c "a lower-case confirm (case-sensitive)" confirm_mismatch "$DEVK" "INPUT_CONFIRM=rotate-$DEVK-$TODAY"
fresh; guard_row C2.9d "a confirm with a trailing space" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-$TODAY "
fresh; guard_row C2.9e "a confirm with a trailing newline" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-$TODAY"$'\n'
fresh; guard_row C2.9f "an empty confirm on rotate" confirm_mismatch "$DEVK" INPUT_CONFIRM=
fresh; guard_row C2.9g "a confirm typed for another key on the right date" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER inngest_signing_key_dev)-$TODAY"
fresh; guard_row C2.9h "a confirm without the key (the old form)" confirm_mismatch "$DEVK" "INPUT_CONFIRM=ROTATE-$TODAY"
fresh; guard_row C2.10 "quiet_window=false" quiet_window_missing "$DEVK" INPUT_QUIET_WINDOW=false
fresh; guard_row C2.11 "GH_TOKEN missing (the run-list reads need it)" credential_absent "$DEVK" GH_TOKEN=
fresh; guard_row C2.12 "egress_audit_ingest_token cannot be rotated (no Vector restart lever without SSH, #11920)" egress_rotate_unsupported_no_vector_restart_lever egress_audit_ingest_token
for k in inngest_manual_trigger_secret_prd kb_drift_ingest_signing_key github_webhook_secret; do fresh; guard_row C2.13 "$k needs the reviewer-gated environment (#11923)" approval_environment_missing "$k"; done
for k in inngest_manual_trigger_secret_dev inngest_signing_key_dev inngest_event_key_dev; do fresh; run_g guard g_rotate "$k"; guard_pass && ok "C2.14 the dev key $k is NOT subject to approval_environment_missing" || bad "C2.14 $k refused: $(verdict_of)"; done
# the later rungs of the three gated keys are reached through a LIFTED tree (the one-line flag the #11923 PR flips)
LIFT_BODY="$TMP/lift-key-rotate.sh"
mutate_file() { # out-file src anchor replacement [func-name]: a landing-checked exact-once edit; prints nothing on success, a reason on failure
  A="$3" R="$4" F="${5:-}" python3 - "$1" "$2" <<'PY'
import os, re, subprocess, sys
out, src = sys.argv[1], sys.argv[2]
a, r, f = os.environ["A"], os.environ["R"], os.environ["F"]
t = open(src).read()
if t.count(a) != 1: print("anchor count %d" % t.count(a)); sys.exit(1)
if f:
    lines = t.split("\n"); idx = t.index(a); ln = t[:idx].count("\n")
    m = [i for i, l in enumerate(lines) if re.match(r"^%s\(\) \{" % re.escape(f), l)]
    if not m: print("function %s not found" % f); sys.exit(1)
    start = m[0]; end = next((i for i in range(start, len(lines)) if lines[i] == "}" or (i == start and lines[i].rstrip().endswith("}") and not lines[i].rstrip().endswith("{"))), None)
    if end is None or not (start <= ln <= end): print("anchor outside %s" % f); sys.exit(1)
open(out, "w").write(t.replace(a, r))
if subprocess.run(["bash", "-n", out]).returncode != 0: print("bash -n failed"); sys.exit(1)
PY
}
MUT_FAIL=""
mut_ok() { local why; why="$(mutate_file "$@")" || { MUT_FAIL="$MUT_FAIL [$1: $why]"; bad "mutation did not land: $(basename "$1")" "$why"; return 1; }; }
mut_ok "$LIFT_BODY" "$BODY" 'KK_APPROVAL_ENV_BOUND=false' 'KK_APPROVAL_ENV_BOUND=true'
RT_LIFT="$TMP/rt-lift"; mk_tree "$RT_LIFT" "$LIFT_BODY"
fresh; run_g guard g_rotate github_webhook_secret; RT="$RT_LIFT" run_g guard g_rotate github_webhook_secret
guard_pass && ok "C2.15 the lifted tree passes the approval rung (the flag is the only difference) for the webhook secret" || bad "C2.15 lifted tree: $(verdict_of)"
fresh; RT="$RT_LIFT" guard_row C2.16 "github_webhook_secret without webhook_patch_ready" webhook_patch_not_ready github_webhook_secret INPUT_WEBHOOK_PATCH_READY=false
fresh; printf '%s' '[{"title":"key-rotate github_webhook_secret owner_step_pending (run 8123)"}]' > "$D/state/issues_owner.json"; RT="$RT_LIFT" guard_row C2.17 "an open owner_step_pending issue for the webhook secret" owner_step_open github_webhook_secret
fresh; printf '%s' '[{"number":5,"title":"key-rotate github_webhook_secret rotated_redeploy_failed (run 8123)"}]' > "$D/state/issues.json"; RT="$RT_LIFT" run_g guard g_rotate github_webhook_secret
guard_pass && ok "C2.18 a rotated_redeploy_failed issue does NOT trigger owner_step_open (only the owner_step_pending label and title do)" || bad "C2.18 refused: $(verdict_of)"
fresh; printf '%s' '[{"title":"key-rotate kb_drift_ingest_signing_key owner_step_pending (run 8123)"}]' > "$D/state/issues_owner.json"; RT="$RT_LIFT" run_g guard g_rotate github_webhook_secret
guard_pass && ok "C2.18b an owner_step_pending title for ANOTHER key does not block the webhook rotate" || bad "C2.18b refused: $(verdict_of)"
fresh; printf '%s' '[{"name":"action-required"}]' > "$D/state/labels.json"; RT="$RT_LIFT" guard_row C2.19 "the owner_step_pending label does not exist (fail closed)" owner_step_open github_webhook_secret
fresh; set_state issue_list_rc 1; RT="$RT_LIFT" guard_row C2.19b "the owner_step_pending listing fails (fail closed)" owner_step_open github_webhook_secret
fresh; jq -cn '[range(0;1000) | {title:("x" + (.|tostring))}]' > "$D/state/issues_owner.json"; RT="$RT_LIFT" guard_row C2.19c "a truncated listing (1000 entries) refuses" owner_step_open github_webhook_secret
# kb_drift windows: the budget is 40 min apply + 85 min redeploy = 7500 s (literal), window [03:00:00, 03:30:00] inclusive
KB=kb_drift_ingest_signing_key
kb_at() { # time expected
  fresh; set_state now "$(at "$1")"; RT="$RT_LIFT" run_g guard g_rotate "$KB"
  if [[ "$2" == ok ]]; then guard_pass && ok "C2.20 kb_drift at $1 UTC is accepted" || bad "C2.20 kb_drift at $1 UTC refused: $(verdict_of)"
  else [[ "$RC" != 0 && "$(verdict_of)" == "$2" ]] && ok "C2.20 kb_drift at $1 UTC is refused ($2)" || bad "C2.20 kb_drift at $1 UTC: $(verdict_of) want $2"; fi
}
kb_at 00:54:59 ok; kb_at 00:55:00 kb_drift_cron_window; kb_at 01:00:00 kb_drift_cron_window; kb_at 02:50:00 kb_drift_cron_window
kb_at 03:00:00 kb_drift_cron_window; kb_at 03:30:00 kb_drift_cron_window; kb_at 03:30:01 ok; kb_at 23:50:00 ok
fresh; set_state now "$(at 02:50:00)"; RT="$RT_LIFT" run_g guard g_rotate inngest_signing_key_dev
guard_pass && ok "C2.21 a dev key at 02:50 UTC is not subject to the kb_drift window" || bad "C2.21 dev key refused: $(verdict_of)"
fresh; set_state now "$(at 04:00:00)"; printf '%s' '[{"databaseId":5}]' > "$D/state/runs_kb-drift-walker.yml_in_progress.json"; RT="$RT_LIFT" guard_row C2.22 "a kb-drift-walker run is in progress" kb_drift_walker_in_flight "$KB"
fresh; set_state now "$(at 04:00:00)"; set_state runlist_rc_kb-drift-walker.yml 1; RT="$RT_LIFT" guard_row C2.22b "the walker query fails (fail closed)" run_list_unreadable "$KB"
fresh; set_state now "$(at 02:50:00)"; mapfile -t _b < <(g_plan "$KB"); RT="$RT_LIFT" run_script guard "${_b[@]}"
eq "C2.23 plan at 02:50 for kb_drift reports the window as a boolean and refuses nothing" "$(guard_pass && echo pass)|$(grep -c 'kb_drift_window_clear=false' <<<"$OUT")" 'pass|1'
# in-flight workflows
for w in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml web-platform-release.yml inngest-key-rotate.yml inngest-link-flip.yml cutover-inngest.yml deploy-inngest-image.yml; do
  fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_${w}_in_progress.json"; guard_row C2.24 "$w has a run in progress" run_in_flight "$DEVK"
done
fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_web-platform-release.yml_pending.json"; guard_row C2.24b "a pending run (the sourced helper does not poll pending)" run_in_flight "$DEVK"
fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_cutover-inngest.yml_requested.json"; guard_row C2.24c "a requested run" run_in_flight "$DEVK"
fresh; set_state runlist_rc 1; guard_row C2.25 "the run list fails (a harness that reads an error as none-in-flight is vacuous)" run_list_unreadable "$DEVK"
fresh; printf '%s' '[{"databaseId":8000}]' > "$D/state/runs_key-rotate.yml_queued.json"; guard_row C2.26 "an EARLIER key-rotate.yml run (lower run id) is still queued" run_in_flight "$DEVK"
fresh; printf '%s' '[{"databaseId":9500},{"databaseId":9001}]' > "$D/state/runs_key-rotate.yml_in_progress.json"; run_g guard g_rotate "$DEVK"
guard_pass && ok "C2.26b a LATER key-rotate.yml run (higher id) and this run itself do not refuse" || bad "C2.26b refused: $(verdict_of)"
# plan mode for all seven keys
for k in $KEYS; do fresh; run_g guard g_plan "$k"; guard_pass && ok "C2.27 plan guard for $k passes with the boolean report" || bad "C2.27 plan guard $k: $(verdict_of)"; done

printf '\n=== C3. apply: plan mode for all seven keys, rotate for the six rotatable keys ===\n'
copies_of() { grep "^$1|" <<<"$COPIES_LIT"; }
snap_hashes() { local k="$1" p c n; while IFS='|' read -r _ p c n; do sha_of_copy "$p" "$c" "$n"; done < <(copies_of "$k") | tr '\n' ' '; }
for k in $KEYS; do
  fresh; before="$(snap_hashes "$k")"; run_g apply a_env plan "$k"
  eq "C3.1 plan for $k: plan_ok, nothing applied, no copy changed, the temp dir is gone" "$RC|$(verdict_of)|$(tfapplied)|$([[ "$(snap_hashes "$k")" == "$before" ]] && echo same)|$(find "$D/rt" -mindepth 1 | wc -l | tr -d ' ')|$(refusals)" '0|plan_ok|0|same|0|0'
done
for k in $ROTATABLE; do
  fresh; before="$(snap_hashes "$k")"; run_g apply a_env rotate "$k"
  after="$(snap_hashes "$k")"; changed=yes; for h in $before; do grep -qw -- "$h" <<<"$after" && changed=no; done
  eq "C3.2 rotate for $k: applied once, write_started=true, every copy changed, no verdict, temp dir gone, no refusal" "$RC|$(tfapplied)|$(out_of write_started)|$changed|$(verdict_of)|$(find "$D/rt" -mindepth 1 | wc -l | tr -d ' ')|$(refusals)" '0|1|true|yes||0|0'
done
fresh; run_g apply a_env rotate "$KB"
eq "C3.3 kb_drift: both copies end equal (one apply)" "$(copy_val soleur prd_kb_drift_walker KB_DRIFT_INGEST_SIGNING_KEY | SHA256_OF)" "$(copy_val soleur prd KB_DRIFT_INGEST_SIGNING_KEY | SHA256_OF)"
fresh; run_g apply a_env rotate inngest_signing_key_dev
eq "C3.3b an inngest_* key replaces BOTH the random_id and the secret (the observed -replace list), a non-ignore key replaces the random_id only" "$(grep '^plan ' "$D/tf.log" | grep -oE 'R (random_id|doppler_secret)\.[a-z_]+' | wc -l | tr -d ' ')" '2'
fresh; run_g apply a_env rotate github_webhook_secret
eq "C3.3c github_webhook_secret: the plan replaces the random_id only (the secret updates in place, no absent window)" "$(grep '^plan ' "$D/tf.log" | grep -oE 'R (random_id|doppler_secret)\.[a-z_]+' | wc -l | tr -d ' ')" '1'
fresh; run_g apply a_env rotate egress_audit_ingest_token
eq "C3.4 egress_audit_ingest_token rotate is refused at apply too (defense in depth), nothing applied" "$RC|$(verdict_of)|$(tfapplied)" '1|egress_rotate_unsupported_no_vector_restart_lever|0'
# pre-write refusals at the first act of apply
fresh; run_g apply a_env rotate "$DEVK" GITHUB_RUN_ATTEMPT=2
eq "C3.5 attempt 2 at apply refuses rerun_refused before any Terraform call and before write_started" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)|$(out_of write_started)" '1|rerun_refused|0|'
fresh; run_g apply a_env rotate "$DEVK" EFF_GUARD_EPOCH=$((NOW0 - 3601))
eq "C3.6 a guard older than 60 minutes: authorization_stale, no Terraform call" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|authorization_stale|0'
fresh; run_g apply a_env rotate "$DEVK" EFF_GUARD_EPOCH=$((NOW0 - 3600))
eq "C3.6b exactly 60 minutes is accepted (the bound is strict)" "$RC|$(verdict_of)|$(tfapplied)" '0||1'
fresh; set_state now "$(( $(at 23:50:00) + 900 ))"; run_g apply a_env rotate "$DEVK" EFF_GUARD_EPOCH="$(at 23:50:00)"
eq "C3.7 the UTC date rolled between the guard and apply (gap 15 min): authorization_stale" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|authorization_stale|0'
fresh; run_g apply a_env rotate "$DEVK" EFF_GUARD_EPOCH=
eq "C3.7b a missing guard_epoch fails closed" "$(verdict_of)" 'authorization_stale'
fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_apply-web-platform-infra.yml_queued.json"; run_g apply a_env rotate "$DEVK"
eq "C3.8 a related run in flight at the first act of apply refuses run_in_flight before any Terraform call" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|run_in_flight|0'
fresh; set_state late_after_web-platform-release.yml_in_progress 1; run_g apply a_env rotate "$DEVK"
eq "C3.8b a release run that appears only on the SECOND read (the pre-apply re-check) leaves the stub apply uncalled and write_started unset" "$RC|$(verdict_of)|$(tfapplied)|$(out_of write_started)" '1|run_in_flight|0|'
fresh; printf '%s' '[{"databaseId":8000}]' > "$D/state/runs_key-rotate.yml_queued.json"; run_g apply a_env rotate "$DEVK"
eq "C3.8c an earlier key-rotate.yml run at apply refuses run_in_flight, no Terraform call" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|run_in_flight|0'
fresh; set_state now "$(at 02:50:00)"; run_g apply a_env rotate "$KB" EFF_GUARD_EPOCH="$(at 02:50:00)"
eq "C3.9 kb_drift: the window is re-checked at the first act of apply (no Terraform call)" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|kb_drift_cron_window|0'
fresh; set_state now "$(at 04:00:00)"; printf '%s' '[{"databaseId":5}]' > "$D/state/runs_kb-drift-walker.yml_queued.json"; run_g apply a_env rotate "$KB" EFF_GUARD_EPOCH="$(at 04:00:00)"
eq "C3.9b kb_drift: a walker in flight at apply start refuses (no Terraform call)" "$RC|$(verdict_of)|$(nlog "$D/tf.log" .)" '1|kb_drift_walker_in_flight|0'
fresh; set_state now "$(at 00:30:00)"; set_state plan_adv 3600; run_g apply a_env rotate "$KB" EFF_GUARD_EPOCH="$(at 00:30:00)"
eq "C3.9c kb_drift: accepted at 00:30, but the plan took an hour: the window is re-checked immediately before the apply and refuses (nothing applied)" "$RC|$(verdict_of)|$(tfapplied)" '1|kb_drift_cron_window|0'
fresh; set_state now "$(at 04:00:00)"; set_state late_after_kb-drift-walker.yml_in_progress 1; run_g apply a_env rotate "$KB" EFF_GUARD_EPOCH="$(at 04:00:00)"
eq "C3.9d kb_drift: a walker run that appears only before the apply refuses (nothing applied)" "$RC|$(verdict_of)|$(tfapplied)" '1|kb_drift_walker_in_flight|0'
fresh; set_state now "$(at 12:00:00)"; set_state plan_adv 3601; run_g apply a_env rotate "$DEVK"
eq "C3.10 the guard's go goes stale DURING the plan: authorization_stale at the pre-apply re-check, nothing applied" "$RC|$(verdict_of)|$(tfapplied)" '1|authorization_stale|0'
fresh; run_g apply a_env rotate "$DEVK" AWS_ACCESS_KEY_ID=
eq "C3.11 a missing Terraform backend credential refuses credential_absent (pre-write)" "$RC|$(verdict_of)|$(out_of write_started)" '1|credential_absent|'
fresh; run_g apply a_env rotate "$DEVK"
OBS="$(cat "$D/apply_obs.log")"
[[ "$OBS" =~ proj=1\ ghcalls=([0-9]+) && "${BASH_REMATCH[1]}" -ge 40 ]] && ok "C3.12 observed INSIDE the window: when the apply ran, the gate's projection existed and the re-check reads (>= 40 gh calls) had already happened" || bad "C3.12 apply observation" "$OBS"

printf '\n=== C4. the gate and the H1 paths ===\n'
gate_row() { # id desc token key setup-fn : a ROTATE apply that must refuse with <token> and apply nothing
  local id="$1" desc="$2" tok="$3" key="$4"; shift 4
  fresh; "$@"; run_g apply a_env rotate "$key"
  if [[ "$RC" != 0 && "$(verdict_of)" == "$tok" && "$(tfapplied)" == 0 && -z "$(out_of write_started)" && "$(refusals)" == 0 ]]; then ok "$id $desc -> $tok, nothing applied"; else bad "$id $desc" "rc=$RC verdict=$(verdict_of) want=$tok applied=$(tfapplied)"; fi
}
A2="doppler_secret.kb_drift_ingest_signing_key_app_runtime"; A1="doppler_secret.kb_drift_ingest_signing_key"; R1="random_id.kb_drift_ingest_signing_key"
st_drop() { touch_state "drop_$A2"; }
gate_row C4.1 "a plan that touches only ONE kb_drift copy (the second is missing)" plan_gate_refused "$KB" st_drop
st_wrong() { printf '%s' '["update"]' > "$D/state/actions_$R1"; }
gate_row C4.2 "a wrong action array on a row (update where delete,create is expected)" plan_gate_refused "$KB" st_wrong
st_extra() { printf '%s' '[{"address":"hcloud_server.web","mode":"managed","type":"hcloud_server","name":"web","change":{"actions":["update"],"before":{},"after":{},"after_unknown":{}}}]' > "$D/state/plan_extra"; }
gate_row C4.3 "an extra address outside the table (hcloud_server)" plan_gate_refused "$KB" st_extra
st_empty() { printf '%s' '{"format_version":"1.2","resource_changes":[]}' > "$D/state/show_raw"; }
gate_row C4.4 "an empty plan (all() over [] is true; the count makes it fail)" plan_gate_refused "$KB" st_empty
st_dup() { touch_state "dup_$R1"; }
gate_row C4.5 "a duplicated row (the change count is 4, the table wants 3)" plan_gate_refused "$KB" st_dup
st_set() { touch_state "dup_$R1"; touch_state "drop_$A1"; }
gate_row C4.6 "the right number of changes but the address SET differs (one row dropped, another duplicated)" plan_gate_refused "$KB" st_set
st_taint() { touch_state "tainted_doppler_secret.$DEVK"; }
gate_row C4.7 "a replace whose reason is not the requested one (replace_because_tainted)" replace_not_requested "$DEVK" st_taint
st_nounk() { touch_state "nounknown_doppler_secret.$DEVK"; }
gate_row C4.8 "a secret row whose value would NOT change (after_unknown.value is not true)" plan_gate_refused "$DEVK" st_nounk
st_abs_a() { touch_state "state_absent_random_id.$DEVK"; }
gate_row C4.9 "a bare create on the random_id row while the paired Doppler copy is PRESENT (a new key nobody asked for)" plan_gate_refused "$DEVK" st_abs_a
st_bare_b() { printf '%s' '["create"]' > "$D/state/actions_doppler_secret.$DEVK"; }
gate_row C4.10 "a bare create on a secret row whose own copy is PRESENT" plan_gate_refused "$DEVK" st_bare_b
st_nonnull() { rm -f "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET"; touch_state "state_absent_random_id.$DEVK"; touch_state "nonnullbefore_doppler_secret.$DEVK"; }
gate_row C4.11 "the copy is absent and the plan creates it, but its before is NOT null (the plan disagrees with the pre-state)" plan_gate_refused "$DEVK" st_nonnull
st_noplan() { set_state plan_rc 1; }
gate_row C4.12 "the Terraform plan step fails" terraform_failed "$DEVK" st_noplan
st_badjson() { printf 'this is not json' > "$D/state/show_raw"; }
gate_row C4.13 "terraform show returns text that is not JSON (a harness that reads it as a pass is vacuous)" terraform_failed "$DEVK" st_badjson
st_emptyjson() { : > "$D/state/show_raw"; }
gate_row C4.14 "an EMPTY projection (terraform show printed nothing)" terraform_failed "$DEVK" st_emptyjson
st_noinit() { set_state init_rc 1; }
gate_row C4.15 "terraform init fails" terraform_failed "$DEVK" st_noinit
fresh; touch_state reverse; run_g apply a_env rotate "$KB"
eq "C4.16 must-PASS, not the canonical fixture: the same rows in REVERSE order plus an unrelated no-op address" "$RC|$(tfapplied)" '0|1'
# H1: every copy absent (an interrupted -replace of both) proceeds; mixed refuses; unreadable refuses
fresh; rm -f "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET"; touch_state "state_absent_random_id.$DEVK"; run_g apply a_env rotate "$DEVK"
eq "C4.17 every copy absent (an interrupted delete-then-create): the bare creates are accepted, the copy is readable and non-empty afterwards, and the redeploy-is-urgent sentence is printed" "$RC|$(tfapplied)|$([[ -s "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET" ]] && echo present)|$(grep -c 'old value survives only in running containers' <<<"$OUT")" '0|1|present|1'
fresh; rm -f "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET"; touch_state "state_absent_random_id.$DEVK"; run_g apply a_env plan "$DEVK"
eq "C4.17b the same absent state in plan mode proceeds to plan_ok" "$(verdict_of)" 'plan_ok'
fresh; rm -f "$D/state/copy_soleur_prd_KB_DRIFT_INGEST_SIGNING_KEY"; run_g apply a_env rotate "$KB"
eq "C4.18 kb_drift with ONE copy absent: partial_absent_state, urgent, nothing applied, no Terraform call" "$RC|$(verdict_of)|$(tfapplied)|$(grep -c 'URGENT' <<<"$OUT")" '1|partial_absent_state|0|1'
fresh; touch_state names_empty_soleur_dev; run_g apply a_env rotate "$DEVK"
eq "C4.19 an EMPTY Doppler name listing is unknown, not absent: copy_unreadable" "$RC|$(verdict_of)|$(tfapplied)" '1|copy_unreadable|0'
fresh; set_state names_rc_soleur_dev 1; run_g apply a_env rotate "$DEVK"
eq "C4.19b a FAILED name listing: copy_unreadable" "$(verdict_of)" 'copy_unreadable'
fresh; touch_state get_junk_fail_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET; run_g apply a_env rotate "$DEVK"
eq "C4.19c a listing that succeeds with a read that FAILS after printing junk (a pipeline without pipefail would hash the junk): copy_unreadable" "$(verdict_of)" 'copy_unreadable'
fresh; touch_state get_empty_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET; run_g apply a_env rotate "$DEVK"
eq "C4.19d a read that succeeds with an EMPTY value hashes to the empty-string hash: copy_unreadable" "$(verdict_of)" 'copy_unreadable'
fresh; rm -f "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET"; : > "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET_PREVIOUS"; touch_state "state_absent_random_id.$DEVK"; run_g apply a_env plan "$DEVK"
eq "C4.19e a superset name (INNGEST_MANUAL_TRIGGER_SECRET_PREVIOUS) in the listing reads as ABSENT (anchored on whole names)" "$(verdict_of)" 'plan_ok'
fresh; run_g apply a_env plan "$DEVK" DOPPLER_TOKEN_TF=
eq "C4.19f no Terraform-scope token: credential_absent" "$(verdict_of)" 'credential_absent'

printf '\n=== C5. post-state: precedence, the retry, failures ===\n'
fresh; touch_state apply_noeffect; run_g apply a_env rotate "$DEVK"
eq "C5.1 value_unchanged: the apply 'succeeded' but a copy did not change (non-zero exit, stop sentence, 2 retries 20 s apart, no write printed as done)" "$RC|$(verdict_of)|$(nlog "$D/sleep.log" 'sleep 20')|$(grep -c '^::error::key-rotate STOP' <<<"$OUT")" '1|value_unchanged|2|1'
fresh; set_state lag_reads 2; run_g apply a_env rotate "$DEVK"
eq "C5.2 Doppler read-after-write lag: unchanged on reads 1 and 2, changed on read 3 must PASS" "$RC|$(verdict_of)|$(nlog "$D/sleep.log" 'sleep 20')" '0||2'
fresh; touch_state "apply_diverge_$A2"; run_g apply a_env rotate "$KB"
eq "C5.3 copies_differ: both kb_drift copies changed but to different values" "$RC|$(verdict_of)" '1|copies_differ'
fresh; touch_state post_get_fail; run_g apply a_env rotate "$DEVK"
eq "C5.4 post_hash_unreadable: the value is unknown, not unchanged" "$RC|$(verdict_of)" '1|post_hash_unreadable'
fresh; touch_state "apply_dropcopy_$A2"; run_g apply a_env rotate "$KB"
eq "C5.5 a copy absent after a successful apply: partial_absent_state" "$RC|$(verdict_of)" '1|partial_absent_state'
fresh; touch_state apply_deletes; run_g apply a_env rotate "$DEVK"
eq "C5.6 an apply that fails after the destroy half: apply_failed, the per-copy classification says absent, the stop sentence is urgent and states the three facts" "$RC|$(verdict_of)|$(grep -c 'post-state copy dev: absent' <<<"$OUT")|$(grep -c 'URGENT' <<<"$OUT")|$(grep -c 'Doppler:.*Terraform state:.*Running containers:' <<<"$OUT")" '1|apply_failed|1|0|1'
fresh; set_state apply_rc 1; run_g apply a_env rotate "$DEVK"
eq "C5.6b a plain apply failure: apply_failed (verdict precedence: the non-zero exit wins over the per-copy classification)" "$RC|$(verdict_of)|$(out_of write_started)" '1|apply_failed|true'
fresh; set_state apply_rc 1; touch_state apply_noeffect; run_g apply a_env rotate "$DEVK"
eq "C5.6c apply_failed with an unchanged copy is still apply_failed (not value_unchanged)" "$(verdict_of)" 'apply_failed'
fresh; touch_state apply_noeffect; touch_state "apply_dropcopy_doppler_secret.$DEVK"; run_g apply a_env rotate "$DEVK"
eq "C5.6d precedence: an absent copy outranks an unchanged one (partial_absent_state before value_unchanged)" "$(verdict_of)" 'partial_absent_state'

printf '\n=== C6. redeploy: three steps ===\n'
r_env() { printf '%s\n' "EFF_MODE=rotate" "EFF_KEY=$1" GH_TOKEN=ghs_fixture "${@:2}"; }
v_env() { printf '%s\n' "EFF_MODE=rotate" "EFF_KEY=$1" "EFF_RECHECK_OUTCOME=${2:-success}" "EFF_TRACK_OUTCOME=${3:-success}" "${@:4}"; }
fresh; run_g "redeploy recheck" r_env "$DEVK"
eq "C6.1 the re-checks pass on a quiet repo" "$RC|$(verdict_of)" '0|'
fresh; run_g "redeploy recheck" r_env "$DEVK"; RT="$RT_REAL" run_script "redeploy recheck" EFF_MODE=rotate "EFF_KEY=$DEVK" GH_TOKEN=ghs_fixture GITHUB_RUN_ATTEMPT=2
eq "C6.2 attempt 2 at the redeploy re-checks: rotated_redeploy_failed (reason rerun_refused), non-zero exit" "$RC|$(verdict_of)|$(grep -c 'reason=rerun_refused' <<<"$OUT")" '1|rotated_redeploy_failed|1'
fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_web-platform-release.yml_in_progress.json"; run_g "redeploy recheck" r_env "$DEVK"
eq "C6.3 a release run in flight at the redeploy start: rotated_redeploy_failed (reason run_in_flight)" "$RC|$(verdict_of)|$(grep -c 'reason=run_in_flight' <<<"$OUT")" '1|rotated_redeploy_failed|1'
fresh; printf '%s' '[{"databaseId":8000}]' > "$D/state/runs_key-rotate.yml_queued.json"; run_g "redeploy recheck" r_env "$DEVK"
eq "C6.3b an earlier key-rotate.yml run at the redeploy start: rotated_redeploy_failed" "$(verdict_of)" 'rotated_redeploy_failed'
fresh; set_state now "$(at 01:36:00)"; run_g "redeploy recheck" r_env "$KB"
eq "C6.4 kb_drift: the window is re-checked at the redeploy start with the remaining 85 minutes (01:36 + 85 min reaches 03:01)" "$RC|$(verdict_of)|$(grep -c 'reason=kb_drift_cron_window' <<<"$OUT")" '1|rotated_redeploy_failed|1'
fresh; set_state now "$(at 01:34:00)"; run_g "redeploy recheck" r_env "$KB"
eq "C6.4b kb_drift at 01:34 (end 02:59) passes the redeploy re-check" "$RC" '0'
fresh; run_script "redeploy track" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 WEBHOOK_DEPLOY_SECRET=fx CF_ACCESS_CLIENT_ID=fx CF_ACCESS_CLIENT_SECRET=fx
eq "C6.5 the track step calls track.sh exactly once with the pinned roster and the 4800 s ceiling, with NO GH_TOKEN in its environment" "$RC|$(cat "$D/track.log")" '0|track WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 REDEPLOY_TIMEOUT_S=4800 GH_TOKEN='
RC_TRACK_LINE="$(cat "$D/track.log")"; [[ "$RC_TRACK_LINE" == *"GH_TOKEN="* && "$RC_TRACK_LINE" != *"GH_TOKEN=set"* ]] && ok "C6.5b track.sh sees no GH_TOKEN" || bad "C6.5b track.log: $RC_TRACK_LINE"
fresh; run_script "redeploy track" WEB_HOST_PRIVATE_IPS=
eq "C6.6 an empty roster refuses to redeploy a single host (track.sh not called)" "$(( RC != 0 ))|$(nlog "$D/track.log" .)" '1|0'
fresh; set_state track_rc 1; run_script "redeploy track" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11
eq "C6.7 track.sh failing is a non-zero step" "$(( RC != 0 ))" '1'
fresh; run_g "redeploy verdict" v_env "$DEVK"
eq "C6.8 verdict: rotate_ok only when both earlier steps succeeded; exit 0" "$RC|$(verdict_of)" '0|rotate_ok'
fresh; run_g "redeploy verdict" v_env "$DEVK" success failure
eq "C6.9 verdict: a failed track step is rotated_redeploy_failed, non-zero, nothing green; the stop sentence names the mixed-fleet case" "$RC|$(verdict_of)|$(grep -c 'MIXED fleet' <<<"$OUT")" '1|rotated_redeploy_failed|1'
fresh; run_g "redeploy verdict" v_env "$DEVK" failure skipped
eq "C6.9b verdict: failed re-checks (track skipped) is rotated_redeploy_failed" "$RC|$(verdict_of)" '1|rotated_redeploy_failed'
fresh; run_g "redeploy verdict" v_env "$DEVK" success cancelled
eq "C6.9c verdict: a cancelled track step is rotated_redeploy_failed" "$(verdict_of)" 'rotated_redeploy_failed'
fresh; run_g "redeploy verdict" v_env github_webhook_secret
eq "C6.10 github_webhook_secret after a good redeploy: owner_step_pending, NON-success, one owner action, neutral wording, no rotate_ok" "$RC|$(verdict_of)|$(grep -c 'rotate_ok' <<<"$OUT")|$(grep -c 'update the GitHub App webhook secret' <<<"$OUT")" '1|owner_step_pending|0|1'
fresh; run_g "redeploy verdict" v_env github_webhook_secret success failure
eq "C6.11 github_webhook_secret after a failed redeploy: the stop sentence says not to update the webhook secret yet" "$RC|$(verdict_of)|$(grep -c 'Do NOT update the GitHub App webhook secret' <<<"$OUT")" '1|rotated_redeploy_failed|1'
fresh; run_g "redeploy verdict" v_env kb_drift_ingest_signing_key success failure
eq "C6.12 kb_drift redeploy failure names the 03:00 UTC walker consequence" "$(grep -c '03:00 UTC' <<<"$OUT")" '1'
fresh; run_g "redeploy verdict" v_env inngest_manual_trigger_secret_prd success failure
eq "C6.13 manual trigger prd redeploy failure names the trigger-cron 401" "$(grep -c 'trigger-cron' <<<"$OUT")" '1'

printf '\n=== C7. notify: the only issue filer ===\n'
n_env() { # key mode apply_result write_started apply_verdict redeploy_result redeploy_verdict
  printf '%s\n' "EFF_MODE=$2" "EFF_KEY=$1" "EFF_RESULT_APPLY=$3" "EFF_WRITE_STARTED=$4" "EFF_APPLY_VERDICT=$5" "EFF_RESULT_REDEPLOY=$6" "EFF_REDEPLOY_VERDICT=$7" GH_TOKEN=ghs_fixture "${@:8}"
}
nrow() { # id desc expected-title-or-"none" key mode ra ws av rr rv
  local id="$1" desc="$2" want="$3"; shift 3; fresh; run_g notify n_env "$@"
  local got; got="$(cut -d'|' -f1 "$D/issues_created.log" 2>/dev/null | sed 's/ $//' | tr '\n' ';')"
  [[ "$want" == none ]] && want=""
  [[ "$want" == "" || "$want" == *";" ]] || want="$want;"
  if [[ "$got" == "$want" && "$(refusals)" == 0 ]]; then ok "$id $desc"; else bad "$id $desc" "filed '$got' want '$want' rc=$RC verdict=$(verdict_of)"; fi
}
nrow C7.1 "write_started=true and the apply failed: files key-rotate <key> apply_failed (run 9001)" "key-rotate $DEVK apply_failed (run 9001)" "$DEVK" rotate failure true apply_failed skipped ""
nrow C7.2 "the apply failed with NO verdict and NO write_started (killed): fails toward filing" "key-rotate $DEVK job_cancelled (run 9001)" "$DEVK" rotate failure "" "" skipped ""
nrow C7.3 "the apply was cancelled: files" "key-rotate $DEVK job_cancelled (run 9001)" "$DEVK" rotate cancelled "" "" skipped ""
nrow C7.4 "a pre-write refusal (rerun_refused) files nothing" none "$DEVK" rotate failure "" rerun_refused skipped ""
nrow C7.4b "a pre-write refusal (plan_gate_refused) files nothing" none "$DEVK" rotate failure "" plan_gate_refused skipped ""
nrow C7.4c "a pre-write refusal (copy_unreadable) files nothing" none "$DEVK" rotate failure "" copy_unreadable skipped ""
nrow C7.4d "a pre-write refusal (credential_absent) files nothing" none "$DEVK" rotate failure "" credential_absent skipped ""
nrow C7.4e "a pre-write refusal (authorization_stale) files nothing" none "$DEVK" rotate failure "" authorization_stale skipped ""
nrow C7.5 "a SKIPPED apply (redaction_ok false) is not a write" none "$DEVK" rotate skipped "" "" skipped ""
nrow C7.6 "partial_absent_state before any write still files the urgent issue" "key-rotate $KB partial_absent_state (run 9001)" "$KB" rotate failure "" partial_absent_state skipped ""
nrow C7.7 "a good apply and a failed redeploy: files rotated_redeploy_failed" "key-rotate $DEVK rotated_redeploy_failed (run 9001)" "$DEVK" rotate success true "" failure rotated_redeploy_failed
nrow C7.8 "a good apply and a redeploy with no verdict (cancelled): job_cancelled, neutral" "key-rotate $DEVK job_cancelled (run 9001)" "$DEVK" rotate success true "" cancelled ""
nrow C7.9 "github_webhook_secret after a good redeploy: files owner_step_pending" "key-rotate github_webhook_secret owner_step_pending (run 9001)" github_webhook_secret rotate success true "" failure owner_step_pending
nrow C7.10 "plan mode files nothing" none "$DEVK" plan failure true apply_failed skipped ""
fresh; run_g notify n_env github_webhook_secret rotate success true "" failure owner_step_pending
eq "C7.11 the owner_step_pending issue carries BOTH labels; the other issues carry action-required only" "$(cat "$D/issues_created.log")" 'key-rotate github_webhook_secret owner_step_pending (run 9001) | labels: action-required owner_step_pending'
fresh; run_g notify n_env "$DEVK" rotate failure true apply_failed skipped ""
eq "C7.11b an apply_failed issue carries action-required only" "$(cat "$D/issues_created.log")" "key-rotate $DEVK apply_failed (run 9001) | labels: action-required"
BODY1="$(cat "$D/issue_body_1.md")"
eq "C7.12 the issue body: run URL, the verdict token, the three facts and the re-dispatch command; nothing about an Inngest route or a converge command" "$(grep -c 'https://github.example/acme/repo/actions/runs/9001' <<<"$BODY1")|$(grep -c 'verdict=apply_failed' <<<"$BODY1")|$(grep -c 'Doppler:.*Terraform state:.*Running containers:' <<<"$BODY1")|$(grep -c 'gh workflow run key-rotate.yml -f mode=rotate -f key=' <<<"$BODY1")|$(grep -ci 'inngest-key-rotate\|converge' <<<"$BODY1")" '1|1|1|1|0'
fresh; printf '%s' "[{\"number\":7,\"title\":\"key-rotate $DEVK apply_failed (run 9001)\"}]" > "$D/state/issues.json"; run_g notify n_env "$DEVK" rotate failure true apply_failed skipped ""
eq "C7.13 de-duplication on (key, token, run): the same event adds a COMMENT and creates nothing" "$(nlog "$D/issues_created.log" .)|$(cat "$D/issues_commented.log" 2>/dev/null)" '0|7'
fresh; printf '%s' "[{\"number\":7,\"title\":\"key-rotate $DEVK apply_failed (run 9001)\"}]" > "$D/state/issues.json"; run_g notify n_env "$DEVK" rotate success true "" failure rotated_redeploy_failed
eq "C7.13b a LATER event of the same run with another token files a new issue" "$(nlog "$D/issues_created.log" .)" '1'
fresh; touch_state create_vanishes; run_g notify n_env "$DEVK" rotate failure true apply_failed skipped ""
eq "C7.14 issue_unfiled: the create call succeeds but the re-list shows no match -> a loud error and a non-zero exit" "$RC|$(verdict_of)|$(grep -c '::error::key-rotate verdict=issue_unfiled' <<<"$OUT")" '1|issue_unfiled|1'
fresh; printf '%s' '[{"name":"action-required"}]' > "$D/state/labels.json"; run_g notify n_env github_webhook_secret rotate success true "" failure owner_step_pending
eq "C7.14b a missing owner_step_pending label: issue_unfiled" "$RC|$(verdict_of)" '1|issue_unfiled'
fresh; jq -cn '[range(0;1000) | {number:., title:"x"}]' > "$D/state/issues.json"; run_g notify n_env "$DEVK" rotate failure true apply_failed skipped ""
eq "C7.14c a truncated open-issue listing: issue_unfiled" "$(verdict_of)" 'issue_unfiled'
fresh; set_state issue_list_rc 1; run_g notify n_env "$DEVK" rotate failure true apply_failed skipped ""
eq "C7.14d a failing open-issue listing: issue_unfiled" "$(verdict_of)" 'issue_unfiled'
fresh; run_g notify n_env github_webhook_secret rotate success true "" cancelled ""
eq "C7.15 the neutral text when the redeploy verdict is missing: check the run, do not update the GitHub App webhook secret until the verdict is read" "$(grep -c 'do not update the GitHub App webhook secret until you have read the verdict' "$D"/issue_body_1.md)" '1'
fresh; printf '%s' "[{\"number\":11,\"title\":\"key-rotate $DEVK apply_failed (run 8000)\"},{\"number\":12,\"title\":\"key-rotate $DEVK owner_step_pending (run 8001)\"},{\"number\":13,\"title\":\"key-rotate $KB apply_failed (run 8002)\"},{\"number\":14,\"title\":\"unrelated\"}]" > "$D/state/issues.json"
run_g notify n_env "$DEVK" rotate success true "" success rotate_ok
eq "C7.16 on rotate_ok the key's earlier open key-rotate issues are closed; an owner_step_pending issue, another key's issue and an unrelated issue are not" "$(sort "$D/issues_closed.log" | tr '\n' ' ')|$(nlog "$D/issues_created.log" .)" '11 |0'

printf '\n=== C8. temp files, dispatch, allowlist, no-stream totals ===\n'
fresh; mapfile -t _e < <(a_env plan "$DEVK"); run_script apply "${_e[@]}"
eq "C8.1 the private temp dir is absent after a normal exit" "$(find "$D/rt" -mindepth 1 | wc -l | tr -d ' ')" '0'
fresh; touch_state plan_sleep
sed -i 's|^  plan)$|  plan) [[ -f "$S/plan_sleep" ]] \&\& sleep 30|' "$D/bin/terraform"
mapfile -t _e < <(a_env plan "$DEVK")
( env -i PATH="$D/bin:$PATH" HOME="$D" STUB="$D" TMPDIR="$D/rt" RUNNER_TEMP="$D/rt" KR_NOW="cat $D/state/now" KR_SLEEP="$D/bin/adv" KR_INFRA_DIR="$D/infra" GITHUB_OUTPUT="$D/gh_output" GITHUB_STEP_SUMMARY="$D/summary" GITHUB_RUN_ID=9001 GITHUB_RUN_ATTEMPT=1 GITHUB_REPOSITORY=acme/repo "${_e[@]}" bash "$RT/scripts/key-rotate.sh" apply >/dev/null 2>&1 & echo $! > "$D/pid"; wait ) &
for _i in $(seq 1 50); do [[ -s "$D/tf.log" ]] && grep -q '^plan' "$D/tf.log" && break; sleep 0.2; done
KILLED_DIR="$(find "$D/rt" -maxdepth 1 -mindepth 1 -type d | head -1)"
pkill -KILL -P "$(cat "$D/pid" 2>/dev/null || echo 0)" 2>/dev/null; kill -KILL "$(cat "$D/pid" 2>/dev/null || echo 0)" 2>/dev/null; wait 2>/dev/null
eq "C8.2 a killed run leaves its temp dir at mode 0700 (nothing world-readable on a shared runner)" "$(stat -c %a "$KILLED_DIR" 2>/dev/null)" '700'
fresh; run_script bogus
eq "C8.3 an unknown subcommand is a usage error (rc 64), never green" "$RC" '64'
fresh; run_script ""
eq "C8.3b no subcommand is a usage error (rc 64)" "$RC" '64'
fresh; run_script "redeploy bogus"
eq "C8.3c an unknown redeploy step is a usage error (rc 64)" "$RC" '64'
xt_rc() { env -i PATH="$PATH" HOME="$TMP" bash -x "$BODY" --print-contract >/dev/null 2>&1; echo $?; }
eq "C8.4 the script refuses to run under xtrace (it handles live credentials)" "$(xt_rc)" '78'
kr_out_probe() { env -i PATH="$PATH" GITHUB_OUTPUT="$TMP/ko.out" bash -c 'source "$1"; : > "$GITHUB_OUTPUT"; kr_out copyhash abc; kr_out verdict "a b"; kr_out verdict "$(printf "x%.0s" {1..80})"; kr_out verdict ok_1; kr_out go true; cat "$GITHUB_OUTPUT" | tr "\n" ";"' _ "${1:-$BODY}"; }
eq "C8.5 the kr_out allowlist: an unknown name, a value with a space and a value over 64 characters never reach GITHUB_OUTPUT; allowed pairs do" "$(kr_out_probe)" 'verdict=ok_1;go=true;'
# the totals
sleep 0.2
SCAN_N="$(wc -l < "$TMP/scans.cnt" | tr -d ' ')"; RUN_N="$(wc -l < "$TMP/runs.cnt" | tr -d ' ')"
eq "C8.6 NO-STREAM: the number of stream scans equals the number of run_script calls ($RUN_N), so no run escaped the scanner" "$SCAN_N" "$RUN_N"
eq "C8.7 NO-STREAM: no run so far leaked a key-shaped string into stdout, stderr, the summary, a job output, an issue body, an annotation or an argv log" "$(wc -l < "$TMP/leaks.log" | tr -d ' ')" '0'
[[ "$(wc -c < "$STREAMS")" -gt 20000 && "$(grep -c 'key-rotate verdict=' "$STREAMS")" -gt 50 ]] && ok "C8.8 the scanner saw real traffic (floor: > 20 kB of streams and > 50 verdict lines)" || bad "C8.8 scanner floor: $(wc -c < "$STREAMS") bytes"

# ---------------------------------------------------------------------------------------------------------------------------
printf '\n=== D. mutations: each guard is removed in a COPY; the scenario that depends on it must change ===\n'
# scenario(script_path -> RT tree): run once against the REAL tree (expect the literal "stops" outcome) and once against a mutated
# COPY made by a landing-checked edit (exactly-once anchor, bash -n, inside the target function); the mutant's outcome is a literal too, so
# a syntax-broken or crashing mutant (an rc-only change) cannot read as caught.
mt() { # name target(body|sib) anchor replacement [func] -> MT_TREE (empty on a failed landing)
  local n="$1" tgt="$2" a="$3" r="$4" f="${5:-}" src="${BASE_BODY:-$BODY}"
  mkdir -p "$TMP/m"; MT_TREE=""
  if [[ "$tgt" == body ]]; then mut_ok "$TMP/m/$n.body" "$src" "$a" "$r" "$f" || return 1; mk_tree "$TMP/mt-$n" "$TMP/m/$n.body"
  else mut_ok "$TMP/m/$n.sib" "${BASE_SIB:-$SIB}" "$a" "$r" "$f" || return 1; mk_tree "$TMP/mt-$n" "${BASE_BODY:-}" "$TMP/m/$n.sib"; fi
  MT_TREE="$TMP/mt-$n"
}
mrow() { # id desc scenario-words want_real want_mut   (uses MT_TREE; skipped when the mutation did not land)
  local id="$1" desc="$2" scen="$3" wr="$4" wm="$5" real mut
  [[ -n "$MT_TREE" ]] || { bad "$id $desc" "mutation did not land"; return; }
  real="$(RT="$RT_REAL"; $scen)"; mut="$(RT="$MT_TREE"; $scen)"
  if [[ "$real" == "$wr" && "$mut" == "$wm" ]]; then ok "$id $desc (stops: '$real'; mutant proceeds: '$mut')"; else bad "$id $desc" "real='$real' want='$wr' | mutant='$mut' want='$wm'"; fi
}
M() { # id desc scen target want_real want_mut anchor repl [func]
  mt "m$((++MUT_N))" "$4" "$7" "$8" "${9:-}" && mrow "$1" "$2" "$3" "$5" "$6"
}
MUT_N=0
v() { local x; x="$(verdict_of)"; printf '%s' "${x:-rc$RC}"; }
a_out() { local x; x="$(verdict_of)"; if [[ "$(tfapplied)" -gt 0 ]]; then printf 'applied%s' "${x:+:$x}"; else printf '%s' "${x:-rc$RC}"; fi; }
st_none() { :; }
sc_guard() { local k="$1"; shift; fresh; mapfile -t _b < <(g_rotate "$k"); run_script guard "${_b[@]}" "$@"; v; }
sc_guard_plan() { local k="$1"; shift; fresh; mapfile -t _b < <(g_plan "$k"); run_script guard "${_b[@]}" "$@"; v; }
sc_confirm() { case "$1" in
  ok) sc_guard "$DEVK" ;; lower) sc_guard "$DEVK" "INPUT_CONFIRM=rotate-$DEVK-$TODAY" ;; suffix) sc_guard "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-$TODAY-X" ;;
  newline) sc_guard "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-$TODAY"$'\n' ;; date) sc_guard "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER "$DEVK")-2001-01-01" ;;
  other) sc_guard "$DEVK" "INPUT_CONFIRM=ROTATE-$(UPPER inngest_signing_key_dev)-$TODAY" ;; esac; }
sc_actor() { local a="$1"; [[ "$a" == BOT ]] && a='x[bot]'; [[ "$a" == EMPTY ]] && a=''; sc_guard "$DEVK" "GITHUB_ACTOR=$a" "GITHUB_TRIGGERING_ACTOR=$a"; }
sc_apply() { local k="$1" setup="$2"; shift 2; fresh; "$setup"; mapfile -t _e < <(a_env rotate "$k"); run_script apply "${_e[@]}" "$@"; a_out; }
sc_apply_tf() { sc_apply "$@"; printf ':tf%s' "$(nlog "$D/tf.log" '^terraform ')"; }
sc_obs() { fresh; mapfile -t _e < <(a_env rotate "$DEVK"); run_script apply "${_e[@]}"; grep -o 'proj=[0-9]' "$D/apply_obs.log" | head -1; }
sc_redeploy_recheck() { fresh; mapfile -t _e < <(r_env "$1"); [[ -n "${2:-}" && "$2" != NONE ]] && set_state now "$(at "$2")"; run_script "redeploy recheck" "${_e[@]}" "${@:3}"; [[ "$RC" == 0 ]] && printf passed || printf '%s' "$(v)"; }
sc_kb_unit() { env -i PATH="$PATH" bash -c 'source "$1"; KR_NOW="echo $2"; kk_chk_kb_window "$3" >/dev/null 2>&1; echo $?' _ "$RT/scripts/key-rotate.sh" "$(at "$1")" "$2"; }
sc_main() { fresh; run_script "$1"; printf 'rc%s' "$RC"; }
sc_ptr() { fresh; run_script "${1:-guard}" "${@:2}"; printf 'rc%s' "$RC"; }
st_late_run() { set_state late_after_web-platform-release.yml_in_progress 1; }
st_kb_walker_late() { set_state now "$(at 04:00:00)"; set_state late_after_kb-drift-walker.yml_in_progress 1; }
st_plan_adv() { set_state plan_adv 3601; }
st_kb_plan_adv() { set_state now "$(at 00:30:00)"; set_state plan_adv 3600; }
st_kb_0250() { set_state now "$(at 02:50:00)"; }
st_earlier() { printf '%s' '[{"databaseId":8000}]' > "$D/state/runs_key-rotate.yml_queued.json"; }
st_walker_now() { set_state now "$(at 04:00:00)"; printf '%s' '[{"databaseId":5}]' > "$D/state/runs_kb-drift-walker.yml_in_progress.json"; }

# --- Guard 1: the gate
BASE_BODY=""; BASE_SIB=""
GATE_ANCH='  if jq -e --argjson want "$want" "$KK_GATE_JQ" "$proj" >/dev/null 2>&1; then return 0; fi'
M D1.1a "gate_true bypass (the gate always passes): a plan touching only one kb_drift copy is applied" "sc_apply $KB st_drop" body "plan_gate_refused" "applied" "$GATE_ANCH" '  return 0' kk_gate
M D1.1b "gate_true bypass: an extra hcloud_server address is applied" "sc_apply $KB st_extra" body "plan_gate_refused" "applied" "$GATE_ANCH" '  return 0' kk_gate
M D1.1c "gate_true bypass: an EMPTY plan is applied" "sc_apply $KB st_empty" body "plan_gate_refused" "applied" "$GATE_ANCH" '  return 0' kk_gate
M D1.1d "gate_true bypass: a wrong action array is applied" "sc_apply $KB st_wrong" body "plan_gate_refused" "applied" "$GATE_ANCH" '  return 0' kk_gate
M D1.2a "jq clause: drop the exact-action clause" "sc_apply $KB st_wrong" body "plan_gate_refused" "applied" '($x.actions == $r.actions' '(true'
M D1.2b "jq clause: drop the change-count clause (duplicate row)" "sc_apply $KB st_dup" body "plan_gate_refused" "applied" '$w > 0 and $n == $w' '$w > 0'
M D1.2c "jq clause: drop the address-set equality clause (right count, wrong set)" "sc_apply $KB st_set" body "plan_gate_refused" "applied" $'  and ((map(.address) | unique) == ($want | map(.address) | unique))\n' ''
M D1.2d "jq clause: drop the before == null recovery condition" "sc_apply $DEVK st_nonnull" body "plan_gate_refused" "applied" $'or ($r.recover and $x.actions == ["create"] and $x.before_null == true' 'or ($r.recover and $x.actions == ["create"]'
M D1.3a "jq clause: drop the action_reason == replace_by_request clause (a tainted replace)" "sc_apply $DEVK st_taint" body "replace_not_requested" "applied" '(if $r.replace then $x.action_reason == "replace_by_request" else true end)' 'true'
M D1.3b "jq clause: drop the after_unknown.value clause (a secret row that would not change)" "sc_apply $DEVK st_nounk" body "plan_gate_refused" "applied" $'and (if $r.recovery then $x.after_unknown_value == true else true end))\n        or ($r.recover' $'and true)\n        or ($r.recover'
M D1.4a "recovery flag: a bare create on the random_id row with a PRESENT paired copy is accepted" "sc_apply $DEVK st_abs_a" body "plan_gate_refused" "applied" 'recover: (if .recovery then ($absent[.address] // false) else $all end)' 'recover: true'
M D1.4b "recovery flag: a bare create on a secret row whose own copy is PRESENT is accepted" "sc_apply $DEVK st_bare_b" body "plan_gate_refused" "applied" 'recover: (if .recovery then ($absent[.address] // false) else $all end)' 'recover: true'
st_all_absent() { rm -f "$D/state/copy_soleur_dev_INNGEST_MANUAL_TRIGGER_SECRET"; touch_state "state_absent_random_id.$DEVK"; }
MT_TREE=""; eq "D1.4c must-PASS arm: with EVERY paired copy absent the same bare creates are accepted on the REAL script" "$(RT="$RT_REAL"; sc_apply "$DEVK" st_all_absent)" 'applied'
M D1.5a "delete the -replace flag generation: a dev (ignore_changes) key plans no change" "sc_apply $DEVK st_none" body "applied" "plan_gate_refused" '  mapfile -t repls < <(kr_gate_replaces A "$key"; kr_gate_replaces B "$key")' '  repls=()' kk_gate_plan
M D1.5b "delete the -replace flag generation: a kb_drift plan changes nothing" "sc_apply $KB st_none" body "applied" "plan_gate_refused" '  mapfile -t repls < <(kr_gate_replaces A "$key"; kr_gate_replaces B "$key")' '  repls=()' kk_gate_plan
proj_keys_of() { code_only "$1" | sed -n "/^KK_PROJECT_JQ=/,/}]'\$/p" | grep -oE '\{address.*\}\]' | grep -oE '[a-z_]+:' | tr -d ':' | tr '\n' ' ' | sed 's/ $//'; }
mt m_proj body 'before_null: (.change.before == null),' 'before_null: (.change.before == null), before: .change.before,' && eq "D1.6 weakening the projection (keeping a before value) breaks the pinned field list" "$(proj_keys_of "$TMP/m/m_proj.body")" "address actions action_reason before_null before after_unknown_value"
eq "D1.6b the pinned field list on the real script is the literal five" "$(proj_keys_of "$BODY")" "$PROJECTED_FIELDS"
# harness rows for Guard 1 live in C4 (invalid JSON, empty projection, reverse-order must-pass)

# --- Guard 2: no stream reaches a log
SIB_REDIRECT='> "$KR_TMP/tf-${name}.out" 2> "$KR_TMP/tf-${name}.err" ) || rc=$?'
sc_sentinels() { # count of sentinel CLASSES visible in the combined streams of a plan run (the scanner's eyes)
  SCAN_ASSERT=0; fresh; mapfile -t _e < <(a_env plan "$DEVK"); run_script apply "${_e[@]}"
  local n=0 s; for s in "$S_B64" "$S_HEX" "$S_SIGN" "$(printf 'x' | SHA256_OF)" "$S_STD" "$S_TOKV"; do grep -qF -- "$s" <<<"$ALL" && n=$((n + 1)); done
  printf 'classes=%s' "$n"
}
BASE_BODY=""; BASE_SIB=""
M D2.1 "the kr_tf redirect replaced by a pass-through (the control run): every sentinel class appears in the captured streams" "sc_sentinels" sib "classes=0" "classes=6" "$SIB_REDIRECT" ') || rc=$?' kr_tf
tf_cmds_of() { code_only "$1" | grep -Ec '(^|[^_a-zA-Z-])terraform[[:space:]]+(init|plan|apply|show|state|output|refresh|destroy|import|console)'; }
mt m_tfcall body '  want="$(kk_want "$key")" || {' $'  terraform plan >/dev/null 2>&1\n  want="$(kk_want "$key")" || {' && eq "D2.2 a bare terraform plan added to the script is seen by the single-call-site check" "$(tf_cmds_of "$BODY")|$(tf_cmds_of "$TMP/m/m_tfcall.body")" '0|1'
eq "D2.3 (workflow) a run: terraform plan step and an upload-artifact step are seen: A39-A41 above (control rows)" "$(tf_hits_in_runs "$TMP/wfv-tf_plan.json")|$(jq -r '[.jobs[].steps[] | (.uses // "") | select(startswith("actions/upload-artifact"))] | length' "$TMP/wfv-upload.json")" '1|1'
sc_issue_leak() { SCAN_ASSERT=0; fresh; mapfile -t _e < <(n_env "$DEVK" rotate failure true apply_failed skipped ""); run_script notify "${_e[@]}" "EFF_DETAIL=$S_HEX"; printf 'hits=%s' "$LAST_HITS"; }
M D2.4 "the issue body includes an unscrubbed detail: the sentinel scan over the issue body copy sees it" "sc_issue_leak" body "hits=0" "hits=1" $'  body="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${run}"$\'\\n\\n\'"verdict=${1}"$\'\\n\\n\'"${2}"$\'\\n\'' $'  body="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${run}"$\'\\n\\n\'"verdict=${1}"$\'\\n\\n\'"${2}"$\'\\n\'"${EFF_DETAIL:-}"' kr_file_issue
: > "$TMP/empty-streams.txt"
floor_ok() { [[ "$(wc -c < "$1")" -gt 20000 && "$(grep -c 'key-rotate verdict=' "$1")" -gt 50 ]]; }
floor_ok "$STREAMS" && ! floor_ok "$TMP/empty-streams.txt" && ok "D2.5 the scanner floor is red on an empty capture directory and green on the real one (a scanner pointed at nothing cannot pass)" || bad "D2.5 scanner floor"

# --- Guard 3: the refusal ladder precedes every write
BASE_BODY=""; BASE_SIB=""
CONFIRM_ANCH='  [[ "${INPUT_CONFIRM:-}" == "$want" ]] && return 0'
M D3.1a "remove the confirm check: a wrong date is accepted" "sc_confirm date" body confirm_mismatch guard_ok $'    kk_check confirm_ok kr_chk_confirm || return 1\n' ''
M D3.1b "remove the confirm check: a confirm typed for another key is accepted" "sc_confirm other" body confirm_mismatch guard_ok $'    kk_check confirm_ok kr_chk_confirm || return 1\n' ''
M D3.1c "confirm compared as a glob prefix: a trailing suffix is accepted" "sc_confirm suffix" body confirm_mismatch guard_ok "$CONFIRM_ANCH" '  [[ "${INPUT_CONFIRM:-}" == "$want"* ]] && return 0' kr_chk_confirm
M D3.1d "nocasematch: a lower-case confirm is accepted" "sc_confirm lower" body confirm_mismatch guard_ok "$CONFIRM_ANCH" $'  shopt -s nocasematch\n  [[ "${INPUT_CONFIRM:-}" == "$want" ]] && return 0' kr_chk_confirm
M D3.1e "a command-substitution compare strips the trailing newline: a confirm with a trailing newline is accepted" "sc_confirm newline" body confirm_mismatch guard_ok "$CONFIRM_ANCH" $'  [[ "$(printf \'%s\' "${INPUT_CONFIRM:-}")" == "$want" ]] && return 0' kr_chk_confirm
eq "D3.1f must-PASS: the correct confirm, exactly as typed, is accepted on the real script" "$(RT="$RT_REAL"; sc_confirm ok)" 'guard_ok'
sc_attempt_guard() { local a="$1"; [[ "$a" == EMPTY ]] && a=''; sc_guard "$DEVK" "GITHUB_RUN_ATTEMPT=$a"; }
M D3.2a "remove the run_attempt check from the guard" "sc_attempt_guard 2" body rerun_refused guard_ok $'    kk_check run_attempt_is_1 kr_chk_attempt || return 1\n' ''
sc_attempt_apply() { sc_apply_tf "$DEVK" st_none "GITHUB_RUN_ATTEMPT=${1:-2}"; }
M D3.2b "remove the run_attempt check from apply (a re-run would bypass the owner's go)" "sc_attempt_apply 2" body "rerun_refused:tf0" "applied:tf4" $'kk_require_attempt() { # <pre|post>\n  kr_chk_attempt && return 0' $'kk_require_attempt() { # <pre|post>\n  return 0'
M D3.2c "remove the run_attempt check from the redeploy re-checks" "sc_redeploy_recheck $DEVK NONE GITHUB_RUN_ATTEMPT=2" body rotated_redeploy_failed passed '  if ! kr_chk_attempt; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi' ''
M D3.2d "the sourced attempt check defaults an unset attempt to 1" "sc_attempt_guard EMPTY" sib rerun_refused guard_ok '"${GITHUB_RUN_ATTEMPT:-}" == 1 ]] && return 0;' '"${GITHUB_RUN_ATTEMPT:-1}" == 1 ]] && return 0;'
M D3.2e "the sourced attempt check is a glob (1*): attempt 10 passes" "sc_attempt_guard 10" sib rerun_refused guard_ok '"${GITHUB_RUN_ATTEMPT:-}" == 1 ]] && return 0;' '"${GITHUB_RUN_ATTEMPT:-}" == 1* ]] && return 0;'
M D3.3a "remove the quiet_window check" "sc_guard $DEVK INPUT_QUIET_WINDOW=false" body quiet_window_missing guard_ok $'    kk_check quiet_window_attested kr_chk_quiet || return 1\n' ''
M D3.3b "remove the [bot] check: x[bot] is no longer refused as a bot" "sc_actor BOT" body actor_refused actor_not_owner '    if [[ -z "$a" || "$a" == *"[bot]" ]]; then' '    if [[ -z "$a" ]]; then'
M D3.3c "an unquoted *[bot] glob refuses any login ending in b, o or t as a bot" "sc_actor Scot" body actor_not_owner actor_refused '    if [[ -z "$a" || "$a" == *"[bot]" ]]; then' '    if [[ -z "$a" || "$a" == *[bot] ]]; then'
M D3.3d "remove the empty-actor check" "sc_actor EMPTY" body actor_refused actor_not_owner '    if [[ -z "$a" || "$a" == *"[bot]" ]]; then' '    if [[ "$a" == *"[bot]" ]]; then'
M D3.3e "remove actor_not_owner: an actor outside the allowlist is accepted" "sc_actor Scot" body actor_not_owner guard_ok '    if [[ "$ok" != 0 ]]; then kr_refuse actor_not_owner' '    if [[ "$ok" != 0 && 1 == 0 ]]; then kr_refuse actor_not_owner'
sc_ref() { sc_guard "$DEVK" GITHUB_REF=refs/heads/feature INPUT_MODE=apply; }
M D3.4a "remove ref_refused from the guard: another rung answers first" "sc_ref" body ref_refused inputs_invalid $'  kr_out go false\n  kk_chk_ref || return 1\n' $'  kr_out go false\n'
sc_pre_ref() { fresh; run_script precondition GITHUB_REF=refs/heads/feature; v; }
M D3.4b "remove ref_refused from the precondition step" "sc_pre_ref" body ref_refused rc0 $'  kr_out redaction_ok false\n  kk_chk_ref || return 1\n' $'  kr_out redaction_ok false\n'
M D3.5a "remove the egress refusal from the guard" "sc_guard egress_audit_ingest_token" body egress_rotate_unsupported_no_vector_restart_lever guard_ok $'    kk_check key_rotatable kk_chk_egress || return 1\n' ''
for k in inngest_manual_trigger_secret_prd $KB github_webhook_secret; do
  M "D3.5b" "remove approval_environment_missing: $k proceeds" "sc_guard $k" body approval_environment_missing guard_ok $'    kk_check approval_environment_bound kk_chk_approval || return 1\n' ''
done
BASE_BODY="$LIFT_BODY"
sc_webhook_ready() { RT="${RT_X:-$RT}"; sc_guard github_webhook_secret INPUT_WEBHOOK_PATCH_READY=false; }
mt mw body $'    kk_check webhook_patch_ready kk_chk_webhook_ready || return 1\n' '' && { real="$(RT="$RT_LIFT"; sc_webhook_ready)"; mut="$(RT="$MT_TREE"; sc_webhook_ready)"; [[ "$real" == webhook_patch_not_ready && "$mut" == guard_ok ]] && ok "D3.5c remove webhook_patch_not_ready (lifted tree): the webhook rotate proceeds without the attestation" || bad "D3.5c webhook_patch_ready" "real='$real' mut='$mut'"; }
st_owner_open() { printf '%s' '[{"title":"key-rotate github_webhook_secret owner_step_pending (run 8123)"}]' > "$D/state/issues_owner.json"; }
sc_owner_open() { fresh; st_owner_open; mapfile -t _b < <(g_rotate github_webhook_secret); run_script guard "${_b[@]}"; v; }
sc_label_missing() { fresh; printf '%s' '[{"name":"action-required"}]' > "$D/state/labels.json"; mapfile -t _b < <(g_rotate github_webhook_secret); run_script guard "${_b[@]}"; v; }
real="$(RT="$RT_LIFT"; sc_owner_open)|$(RT="$RT_LIFT"; sc_label_missing)"
eq "D3.9-pre (lifted tree) the owner_step_open scenarios stop" "$real" 'owner_step_open|owner_step_open'
mt mo body $'  [[ "$key" == github_webhook_secret ]] && { kk_check owner_step_clear kk_chk_owner_step || { kk_guard_report; return 1; }; }\n' '' && { real="$(RT="$RT_LIFT"; sc_owner_open)"; mut="$(RT="$MT_TREE"; sc_owner_open)"; [[ "$real" == owner_step_open && "$mut" == guard_ok ]] && ok "D3.9a delete owner_step_open: a github rotate with the owner step open proceeds" || bad "D3.9a owner_step_open" "real='$real' mut='$mut'"; }
mt ml body $'  if ! jq -e \'any(.[]; .name == "owner_step_pending")\' <<<"$labels" >/dev/null 2>&1; then' '  if false; then' && { real="$(RT="$RT_LIFT"; sc_label_missing)"; mut="$(RT="$MT_TREE"; sc_label_missing)"; [[ "$real" == owner_step_open && "$mut" == guard_ok ]] && ok "D3.9b delete the label-exists check: a missing label proceeds" || bad "D3.9b label" "real='$real' mut='$mut'"; }
BASE_BODY=""
M D3.6a "an unknown subcommand falls through to success (the '0 checked and green' mutant)" "sc_main bogus" body rc64 rc0 $'    *) printf \'usage: %s --print-contract|precondition|guard|apply|redeploy recheck|track|verdict|notify\\n\' "${0##*/}" >&2; return 64 ;;' '    *) return 0 ;;' main
M D3.6b "an empty mode is accepted (rotate-only checks are skipped as if it were plan)" "sc_guard $DEVK INPUT_MODE=" body inputs_invalid guard_ok '  case "${1:-}" in plan|rotate) ;; *) kr_refuse inputs_invalid "mode must be plan or rotate"; return 1 ;; esac' '  case "${1:-}" in plan|rotate) ;; *) ;; esac' kk_valid_inputs
# reorder: the gate AFTER the apply, observed inside the window
M D3.7a "REORDER: the gate runs after the apply (the stub apply observes whether the projection existed)" "sc_obs" body "proj=1" "proj=0" $'  kk_gate_plan "$key" p || return 1\n  if [[ "$mode" == plan ]]; then' $'  if [[ "$mode" == plan ]]; then'
M D3.7b "REORDER: the final pre-apply re-check runs AFTER the apply (the late run is only seen when it is too late)" "sc_apply $DEVK st_late_run" body run_in_flight "applied:run_in_flight" $'  kk_chk_stale || return 1\n  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n  kr_out write_started true\n  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-p" || rc=$?\n' $'  kr_out write_started true\n  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-p" || rc=$?\n  kk_chk_stale || return 1\n  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n'
# re-checks deleted one at a time
sc_stale_start() { sc_apply_tf "$DEVK" st_none EFF_GUARD_EPOCH=$((NOW0 - 3601)); }
M D3.8a "delete authorization_stale at the start of apply (the pre-apply check still refuses, but only after init and two plans)" "sc_stale_start" body "authorization_stale:tf0" "authorization_stale:tf3" $'    kk_chk_stale || return 1\n    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S"' $'    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S"'
M D3.8b "delete authorization_stale before the apply (the go goes stale during the plan)" "sc_apply $DEVK st_plan_adv" body authorization_stale "applied" $'  kk_chk_stale || return 1\n  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S"' $'  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S"'
M D3.8c "delete the in-flight/kb re-check before the apply (a release run appears during the plan)" "sc_apply $DEVK st_late_run" body run_in_flight "applied" $'  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n' ''
M D3.8d "delete the kb_drift window re-check before the apply (the plan took an hour)" "sc_apply $KB st_kb_plan_adv EFF_GUARD_EPOCH=$(at 00:30:00)" body kb_drift_cron_window "applied" $'  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n' ''
M D3.8e "delete the walker re-check before the apply (a walker appears during the plan)" "sc_apply $KB st_kb_walker_late EFF_GUARD_EPOCH=$(at 04:00:00)" body kb_drift_walker_in_flight "applied" $'  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n' ''
M D3.8f "delete the re-check at the start of apply (the pre-apply re-check refuses later, after init and the plan)" "sc_apply_tf $DEVK st_earlier" body "run_in_flight:tf0" "run_in_flight:tf3" $'    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n' ''
M D3.8g "delete the kb_drift re-check at the redeploy start" "sc_redeploy_recheck $KB 01:36:00" body rotated_redeploy_failed passed '  if ! kk_recheck "$EFF_KEY" "$KK_KB_BUDGET_REDEPLOY_S"; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi' ''
M D3.8h "delete the in-flight re-check at the redeploy start" "sc_redeploy_recheck $DEVK NONE" body passed passed '  if ! kk_recheck "$EFF_KEY" "$KK_KB_BUDGET_REDEPLOY_S"; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi' ''
sc_redeploy_inflight() { fresh; printf '%s' '[{"databaseId":4242}]' > "$D/state/runs_web-platform-release.yml_in_progress.json"; mapfile -t _e < <(r_env "$DEVK"); run_script "redeploy recheck" "${_e[@]}"; [[ "$RC" == 0 ]] && printf passed || v; }
M D3.8i "delete the in-flight re-check at the redeploy start (a release run is in flight)" "sc_redeploy_inflight" body rotated_redeploy_failed passed '  if ! kk_recheck "$EFF_KEY" "$KK_KB_BUDGET_REDEPLOY_S"; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi' ''
M D3.8j "delete the kb_drift window re-check at the start of apply" "sc_apply_tf $KB st_kb_0250 EFF_GUARD_EPOCH=$(at 02:50:00)" body "kb_drift_cron_window:tf0" "kb_drift_cron_window:tf3" $'    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }\n' ''
sc_lower_guard() { fresh; st_earlier; mapfile -t _b < <(g_rotate "$DEVK"); run_script guard "${_b[@]}"; v; }
M D3.9c "delete the lower-run-id rung from the guard" "sc_lower_guard" body run_in_flight guard_ok $'  kk_check no_earlier_run kk_chk_lower_run || { kk_guard_report; return 1; }\n' ''
M D3.9d "delete the lower-run-id rung from the re-checks (apply)" "sc_apply_tf $DEVK st_earlier" body "run_in_flight:tf0" "applied:tf4" $'  kk_chk_lower_run || return 1\n' ''
# kb boundaries (literal seconds); the unit scenario calls kk_chk_kb_window directly
M D3.10a "flip <= to < at the 03:30 edge: a dispatch at exactly 03:30:00 is accepted" "sc_kb_unit 03:30:00 7500" body 1 0 '    if (( now <= we && now + b >= ws )); then' '    if (( now < we && now + b >= ws )); then' kk_chk_kb_window
M D3.10b "flip >= to > at the start edge: a dispatch whose budget ends exactly at 03:00:00 is accepted" "sc_kb_unit 00:55:00 7500" body 1 0 '    if (( now <= we && now + b >= ws )); then' '    if (( now <= we && now + b > ws )); then' kk_chk_kb_window
M D3.10c "drop the midnight wrap (tomorrow's window): a long budget from 23:50 reaches the next 03:00" "sc_kb_unit 23:50:00 36000" body 1 0 '  for d in 0 1; do' '  for d in 0; do' kk_chk_kb_window
eq "D3.10d the boundary table on the real function: 00:54:59 ok, 00:55:00 refused, 03:30:00 refused, 03:30:01 ok, 23:50:00 (7500 s) ok" "$(for t in 00:54:59 00:55:00 03:30:00 03:30:01 23:50:00; do RT="$RT_REAL" sc_kb_unit "$t" 7500; done | tr '\n' ' ')" '0 1 1 0 0 '
BASE_BODY="$LIFT_BODY"
sc_walker_guard() { fresh; st_walker_now; mapfile -t _b < <(g_rotate "$KB"); run_script guard "${_b[@]}"; v; }
sc_window_guard() { fresh; st_kb_0250; mapfile -t _b < <(g_rotate "$KB"); run_script guard "${_b[@]}"; v; }
for cs in "walker|kb_drift_walker_clear|sc_walker_guard|kb_drift_walker_in_flight" "window|kb_drift_window_clear|sc_window_guard|kb_drift_cron_window"; do
  IFS='|' read -r nm chk fn want <<<"$cs"
  mt "mk$nm" body "    kk_check $chk kk_chk_$( [[ $nm == walker ]] && echo walker || echo kb_window ) || { kk_guard_report; return 1; }"$'\n' '' && { real="$(RT="$RT_LIFT"; $fn)"; mut="$(RT="$MT_TREE"; $fn)"; [[ "$real" == "$want" && "$mut" == guard_ok ]] && ok "D3.10e drop the $nm rung at the guard (lifted tree)" || bad "D3.10e $nm" "real='$real' mut='$mut'"; }
done
BASE_BODY=""

# --- Guard 4: reuse integrity
BASE_SIB=""
sc_contract_rc() { fresh; run_script --print-contract; printf 'rc%s' "$RC"; }
sc_plan_apply() { fresh; mapfile -t _e < <(a_env plan "$DEVK"); run_script apply "${_e[@]}"; printf '%s:tf%s' "$(v)" "$(nlog "$D/tf.log" '^terraform ')"; }
M D4.1a "rename kr_tf in a copy of the sourced script: the script exits 78 before any Terraform call" "sc_plan_apply" sib "plan_ok:tf3" "rc78:tf0" 'kr_tf() {' 'kr_tf_x() {'
M D4.1b "rename kr_tf: even --print-contract refuses (the type check precedes everything)" "sc_contract_rc" sib "rc0" "rc78" 'kr_tf() {' 'kr_tf_x() {'
M D4.2a "KR_GATE_TABLE becomes a scalar in the copy" "sc_contract_rc" sib "rc0" "rc78" 'KR_GATE_TABLE=(' $'KR_GATE_TABLE="scalar"\nKR_GATE_TABLE_UNUSED=('
M D4.2b "KR_GATE_TABLE becomes readonly in the copy" "sc_contract_rc" sib "rc0" "rc78" 'KR_GATE_TABLE=(' 'declare -ar KR_GATE_TABLE=('
trap_count() { code_only "$1" | grep -Ec '(^|[[:space:];])trap '; }; sete_count() { code_only "$1" | grep -Ec '(^|[[:space:];])set +-[a-zA-Z]*e'; }
sc_tmp_left() { fresh; mapfile -t _e < <(a_env plan "$DEVK"); run_script apply "${_e[@]}"; printf 'left=%s' "$(find "$D/rt" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"; }
BASE_SIB=""
M D4.4a "add a trap 'x' EXIT after kr_init (it replaces the sourced cleanup trap): the key-bearing temp dir is left behind" "sc_tmp_left" body "left=0" "left=1" $'  kr_init || return 1\n  if [[ "$mode" == rotate ]]; then\n    kk_require_attempt || return 1' $'  kr_init || return 1\n  trap \'x\' EXIT\n  if [[ "$mode" == rotate ]]; then\n    kk_require_attempt || return 1'
eq "D4.4b the static trap/set -e counts see an added trap and an added set -e (real: 0 and 0)" "$(trap_count "$BODY")|$(sete_count "$BODY")|$(trap_count "$TMP/m/m$MUT_N.body")" "0|0|1"
mt mse body $'set -uo pipefail\n\ncase "$-" in' $'set -euo pipefail\n\ncase "$-" in' && eq "D4.4c adding set -e is seen by the static check and changes the happy path" "$(sete_count "$TMP/m/mse.body")|$(RT="$MT_TREE"; sc_plan_apply)" '1|rc1:tf1' || true
pin_of() { local t="" f; for f in $SOURCED_CALLED; do t+="$(fn_text "$f" "$1")"$'\n'; done; t+="$(grep '^KR_EMPTY_SHA=' "$1")"$'\n'; printf '%s' "$t" | SHA256_OF; }
mt msib sib '-e '"'"'s/[A-Za-z0-9_-]{41,}/<token-redacted>/g'"'"' \' '-e '"'"'s/[A-Za-z0-9_-]{51,}/<token-redacted>/g'"'"' \' kr_scrub && eq "D4.5a editing ONE sourced function body (kr_scrub) changes the pinned sha256" "$([[ "$(pin_of "$SIB")" == "$SOURCED_PIN" ]] && echo pinned)|$([[ "$(pin_of "$TMP/m/msib.sib")" != "$SOURCED_PIN" ]] && echo differs)" 'pinned|differs'
mt mpfx sib 'inngest-key-rotate.XXXXXX' 'x-rotate.XXXXXX' kr_init && eq "D4.5b editing the temp prefix inside kr_init changes the pin and the prefix check" "$([[ "$(pin_of "$TMP/m/mpfx.sib")" != "$SOURCED_PIN" ]] && echo differs)|$(fn_text kr_init "$TMP/m/mpfx.sib" | grep -c 'inngest-key-rotate.XXXXXX')" 'differs|0'
# the loop: delete each same-name redefinition once; the battery (leak scan over output, argv logs and issue bodies, plus must-pass expectations) must turn
sc_battery() {
  local bad=0 all="" x
  fresh; mapfile -t _b < <(g_rotate "$DEVK"); run_script guard "${_b[@]}"; all+="$ALL"; [[ "$(verdict_of)" == guard_ok ]] || bad=$((bad + 1))
  fresh; mapfile -t _b < <(g_rotate "$DEVK"); run_script guard "${_b[@]}" INPUT_QUIET_WINDOW=false; all+="$ALL"; [[ "$(verdict_of)" == quiet_window_missing ]] || bad=$((bad + 1))
  fresh; touch_state apply_noeffect; mapfile -t _e < <(a_env rotate "$DEVK"); run_script apply "${_e[@]}"; all+="$ALL"; [[ "$(verdict_of)" == value_unchanged && "$OUT" == *"STOP: "* ]] || bad=$((bad + 1))
  fresh; mapfile -t _e < <(v_env github_webhook_secret); run_script "redeploy verdict" "${_e[@]}"; all+="$ALL"; [[ "$(verdict_of)" == owner_step_pending ]] || bad=$((bad + 1))
  fresh; mapfile -t _e < <(n_env "$DEVK" rotate failure true apply_failed skipped ""); run_script notify "${_e[@]}"; all+="$ALL"$'\n'"$(cat "$D"/issue_body_*.md "$D/gh.log" 2>/dev/null)"; [[ "$(cut -d'|' -f1 "$D/issues_created.log" 2>/dev/null | sed 's/ $//')" == "key-rotate $DEVK apply_failed (run 9001)" ]] || bad=$((bad + 1))
  fresh; run_script --print-contract; all+="$ALL"; [[ "$(head -1 <<<"$OUT")" == "key-rotate verdict-tokens" ]] || bad=$((bad + 1))
  fresh; run_script bogus; all+="$ALL"; [[ "$RC" == 64 ]] || bad=$((bad + 1))
  fresh; run_script precondition; all+="$ALL"; [[ "$RC" == 0 && "$(out_of redaction_ok)" == true ]] || bad=$((bad + 1))
  x="$(env -i PATH="$PATH" GITHUB_OUTPUT="$TMP/kb.out" bash -c 'source "$1"; : > "$GITHUB_OUTPUT"; kr_out copyhash abc; kr_out go true; cat "$GITHUB_OUTPUT"' _ "$RT/scripts/key-rotate.sh" 2>&1)"; [[ "$x" == "go=true" ]] || bad=$((bad + 1))
  # the sourced mktemp prefix (inngest-key-rotate.XXXXXX, pinned by CTO F1) legitimately appears in the --body-file argv path; strip it
  all="$(sed -E 's#inngest-key-rotate\.[A-Za-z0-9]{6}#TMPDIR#g' <<<"${all//inngest-key-rotate.yml/}")"
  x="$(grep -i 'inngest-key-rotate\|converge' <<<"$all" | wc -l | tr -d ' ')"
  [[ "$bad" == 0 && "$x" == 0 ]] && printf clean || printf 'dirty:b%s:l%s' "$bad" "$x"
}
delete_fn() { # out src name: removes a top-level function block (landing: exactly one, bash -n)
  python3 - "$1" "$2" "$3" <<'PY'
import re, subprocess, sys
out, src, n = sys.argv[1:4]
lines = open(src).read().split("\n")
idx = [i for i, l in enumerate(lines) if re.match(r"^%s\(\) \{" % re.escape(n), l)]
if len(idx) != 1: print("count %d" % len(idx)); sys.exit(1)
s = idx[0]; e = s if (lines[s].rstrip().endswith("}") and not lines[s].rstrip().endswith("{")) else next(i for i in range(s, len(lines)) if lines[i] == "}")
open(out, "w").write("\n".join(lines[:s] + lines[e + 1:]))
if subprocess.run(["bash", "-n", out]).returncode != 0: sys.exit(1)
PY
}
BATTERY_REAL="$(RT="$RT_REAL"; sc_battery)"
eq "D4.6-0 the override battery is clean on the real script (output, argv logs and issue bodies carry no Inngest-route or converge text; every expected outcome holds)" "$BATTERY_REAL" 'clean'
for fnm in $OVERRIDES kr_out; do
  if delete_fn "$TMP/m/del-$fnm.body" "$BODY" "$fnm" >/dev/null 2>&1; then
    mk_tree "$TMP/mt-del-$fnm" "$TMP/m/del-$fnm.body"; res="$(RT="$TMP/mt-del-$fnm"; sc_battery)"
    [[ "$res" != clean && "$res" == dirty:* ]] && ok "D4.6 deleting the redefinition of $fnm turns the battery ($res)" || bad "D4.6 deleting $fnm is invisible to the battery" "$res"
  else bad "D4.6 could not delete $fnm"; fi
done
# harness rows for Guard 4
{ cat "$SIB" | sed '$d'; printf 'kr_unrelated_extra() { :; }\n'; tail -n 1 "$SIB"; } > "$TMP/m/extra.sib"
mk_tree "$TMP/mt-extra" "" "$TMP/m/extra.sib"
eq "D4.H1 harness (a): a copy of the sourced script with an extra, unrelated function still PASSES the symbol check" "$(RT="$TMP/mt-extra"; sc_contract_rc)" 'rc0'
: > "$TMP/m/decoy.sib"; mk_tree "$TMP/mt-decoy" "" "$TMP/m/decoy.sib"
eq "D4.H2 harness (b): a decoy (empty) path for the sourced script makes setup FAIL instead of passing" "$(RT="$TMP/mt-decoy"; sc_contract_rc)" 'rc78'

# --- final accounting for the whole run
sleep 0.2
SCAN_N="$(wc -l < "$TMP/scans.cnt" | tr -d ' ')"; RUN_N="$(wc -l < "$TMP/runs.cnt" | tr -d ' ')"
eq "D9.1 NO-STREAM (whole suite incl. mutation scenarios): the number of stream scans equals the number of run_script calls ($RUN_N)" "$SCAN_N" "$RUN_N"
eq "D9.2 NO-STREAM (whole suite): zero leaks outside the deliberate control and issue-leak scenarios" "$(wc -l < "$TMP/leaks.log" | tr -d ' ')" '0'
[[ -z "$MUT_FAIL" ]] && ok "D9.3 every mutation landed (exactly-once anchor, bash -n, inside the target function)" || bad "D9.3 mutations that did not land" "$MUT_FAIL"

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
FLOOR=385
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
if (( PASS + FAIL > FLOOR )); then
  printf 'FAIL FLOOR DRIFT: %d assertions ran but FLOOR is %d - set FLOOR=%d (the floor is the real count)\n' $((PASS + FAIL)) "$FLOOR" $((PASS + FAIL)) >&2
  exit 1
fi
exit $(( FAIL > 0 ))
