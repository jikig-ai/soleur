#!/usr/bin/env bash
# =============================================================================
# Shape pins for apply-github-infra.yml::apply's soleur-infra App token (#9360).
#
# The two older consumers of .github/actions/mint-infra-app-token carry shape rows
# (test-bump-inngest-bootstrap-pin.sh S16/S18/S19/S24, test-mint-inngest-bootstrap-tag.sh
# w12-w16); the third consumer gets the same here. The PROPERTY: the job is Tier B; it
# mints exactly one token, from the whole Tier-B project named EXPLICITLY through the
# composite's validated doppler-project input (the composite's default is the narrow
# soleur-infra-app project, which the broad token cannot read), with the broad
# DOPPLER_TOKEN_INFRA_PRIVILEGED secret, scoped exactly as declared, before any
# Terraform or Doppler-run step, failing the job if the mint fails; the token reaches only
# the verify step and the revoke step, through env:, never $GITHUB_ENV or ${{ }} in run:;
# and the last step revokes it on every path where the mint succeeded.
#
# Since #9362 the file also pins two more properties. GUARD 2: the apply job passes no
# prd_terraform value to Terraform (no doppler-run wrapper, no tf-var name transformer, no Tier-A
# DOPPLER_TOKEN in any step but the backend-key read, no download-to-env step), and the by-value
# gate step sits between plan and apply with exactly two invocations. GUARD 1: that gate script
# (scripts/verify-ruleset-required-checks.sh) is driven over plans built at run time from a real
# `terraform show -json` capture, and a stub that always exits 0 must turn this suite RED.
#
# The checker runs once on the real workflow (must PASS) and once per mutation on a copy
# (each must FAIL, and for the reason it names). Verdicts read an append-only ledger;
# the floor and the ledger reconciliation report via printf + exit, never via fail().
# =============================================================================
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-github-infra.yml"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

passes=0; fails=0; FAILURES=()
pass() { passes=$((passes + 1)); echo "  ok   $1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); echo "  FAIL $1${2:+ — $2}"; }

# Instrument self-test (ADR-193): both helpers move their counters, in a subshell.
_st="$( (pass st >/dev/null; fail st >/dev/null; printf '%s,%s,%s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [[ "$_st" != "1,1,1" ]]; then
  printf 'FAIL INSTRUMENT: pass/fail self-test read "%s", want "1,1,1"\n' "$_st" >&2; exit 1
fi

cat > "$T/check.py" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get("jobs") or {}).get("apply") or {}
steps = [s for s in (job.get("steps") or []) if isinstance(s, dict)]
bad = []
def need(cond, reason):
    if not cond:
        bad.append(reason)

need(job.get("environment") == "infra-privileged", "env:job-not-infra-privileged")
mints = [i for i, s in enumerate(steps) if str(s.get("uses", "")).startswith("./.github/actions/mint-infra-app-token")]
need(len(mints) == 1, "mint:count=%d" % len(mints))
if len(mints) == 1:
    mi = mints[0]; m = steps[mi]; w = m.get("with") or {}
    need(m.get("id") == "mint", "mint:id")
    need(w.get("doppler-project") == "soleur-infra-privileged", "mint:doppler-project")
    need(w.get("doppler-token") == "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}", "mint:doppler-token")
    need(str(w.get("installation-id")) == "166065653", "mint:installation-id")
    need(w.get("permissions") == '{"administration":"write"}', "mint:permissions")
    need(w.get("repositories") == "soleur-marketplace", "mint:repositories")
    need("continue-on-error" not in m and "if" not in m, "mint:may-be-skipped-or-tolerated")
    loader = [i for i, s in enumerate(steps) if str(s.get("uses", "")).startswith("./.github/actions/infra-credentials")]
    need(len(loader) == 1 and loader[0] < mi, "mint:not-after-loader")
    first_write = [i for i, s in enumerate(steps) if "doppler run" in str(s.get("run", "")) or "terraform " in str(s.get("run", ""))]
    need(first_write and mi < first_write[0], "mint:not-before-first-doppler-run-or-terraform")
TOK = "steps.mint.outputs.token"
holders = [s.get("name", "") for s in steps if any(TOK in str(v) for v in (s.get("env") or {}).values())]
need(holders == ["Post-apply verify (ruleset required check counts — CI 14145388 + CLA 13304872)", "Revoke the soleur-infra token"], "token:holders=%s" % holders)
need(not any(TOK in str(s.get("run", "")) for s in steps), "token:interpolated-in-run")
need(not any("GITHUB_ENV" in str(s.get("run", "")) and "INSTALL_TOKEN" in str(s.get("run", "")) for s in steps), "token:written-to-GITHUB_ENV")
last = steps[-1] if steps else {}
need(last.get("name") == "Revoke the soleur-infra token", "revoke:not-last")
need(last.get("if") == "always() && steps.mint.outcome == 'success'", "revoke:condition")
need((last.get("env") or {}).get("REVOKE_TOKEN") == "${{ steps.mint.outputs.token }}", "revoke:token-source")
need("installation/token" in str(last.get("run", "")) and "DELETE" in str(last.get("run", "")), "revoke:no-DELETE")
# --- Guard 2 (#9362): the apply job passes no prd_terraform value to Terraform ---
import re
need(len(steps) > 0, "g2:no-steps")
BACKEND = "Extract backend credentials"
GATE = "Gate planned required-check bindings (by value, pre-apply)"
for st in steps:
    run, nm = str(st.get("run", "")), st.get("name", "?")
    if "doppler run" in run or "--name-transformer" in run:
        bad.append("g2:wrapper:%s" % nm)
    if "doppler secrets download" in run:
        bad.append("g2:secrets-download:%s" % nm)
    if re.search(r"TF_VAR_[A-Za-z0-9_]+\s*=", run):
        bad.append("g2:tf-var-assignment:%s" % nm)
    if "GITHUB_ENV" in run and nm != BACKEND:
        bad.append("g2:github-env-write:%s" % nm)
    if "DOPPLER_TOKEN" in (st.get("env") or {}) and nm != BACKEND:
        bad.append("g2:doppler-token-env:%s" % nm)
got = set(re.findall(r"doppler secrets get ([A-Za-z0-9_]+)", "\n".join(str(st.get("run", "")) for st in steps)))
need(got == {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"}, "g2:secrets-get-names=%s" % sorted(got))
gi = [i for i, st in enumerate(steps) if st.get("name") == GATE]
pi = [i for i, st in enumerate(steps) if st.get("name") == "Terraform plan"]
ai = [i for i, st in enumerate(steps) if st.get("name") == "Terraform apply"]
need(len(gi) == 1 and len(pi) == 1 and len(ai) == 1, "g2:gate-missing")
if len(gi) == 1 and len(pi) == 1 and len(ai) == 1:
    gs = steps[gi[0]]; grun = str(gs.get("run", ""))
    need(pi[0] < gi[0] < ai[0], "g2:gate-order")
    need(gs.get("working-directory") == "${{ env.INFRA_DIR }}", "g2:gate-working-directory")
    need("continue-on-error" not in gs and "if" not in gs, "g2:gate-may-be-skipped")
    need("set -euo pipefail" in grun, "g2:gate-pipefail")
    need("set -x" not in grun and "xtrace" not in grun, "g2:gate-xtrace")
    flat = re.sub(r"\s*\\\n\s*", " ", grun)
    lines = [l for l in flat.splitlines() if "verify-ruleset-required-checks.sh" in l]
    pat = re.compile(r'terraform show -json tfplan \| bash "(\$\{GITHUB_WORKSPACE\}/scripts/verify-ruleset-required-checks\.sh)" - (github_repository_ruleset\.[a-z_]+) "(\$\{GITHUB_WORKSPACE\}/scripts/[A-Za-z0-9_.-]+\.json)"\s*$')
    ms = [pat.search(l) for l in lines]
    need(len(lines) == 2, "g2:gate-invocations=%d" % len(lines))
    need(all(ms), "g2:gate-path-or-shape")
    want = {"github_repository_ruleset.ci_required": "${GITHUB_WORKSPACE}/scripts/ci-required-ruleset-canonical-required-status-checks.json",
            "github_repository_ruleset.cla_required": "${GITHUB_WORKSPACE}/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"}
    need(all(ms) and {m.group(2): m.group(3) for m in ms} == want, "g2:gate-address-canonical-map")
print("PASS" if not bad else "FAIL " + " ".join(bad))
PY

echo "--- control (the real workflow)"
ctl="$(python3 "$T/check.py" "$WF")"
if [[ "$ctl" == "PASS" ]]; then pass "C0: apply-github-infra.yml::apply holds every shape pin"
else fail "C0: the real workflow fails a shape pin" "$ctl"; fi

echo "--- mutations (each must FAIL for its named reason)"
row() { # <name> <expected reason substring> <python replace: old> <new> [<old2> <new2>]
  local name="$1" want="$2" out
  cp "$WF" "$T/m.yml"
  if ! python3 - "$T/m.yml" "$3" "$4" "${5:-}" "${6:-}" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
pairs = [(sys.argv[2], sys.argv[3])]
if sys.argv[4]:
    pairs.append((sys.argv[4], sys.argv[5]))
for old, new in pairs:
    if s.count(old) != 1:
        sys.exit("anchor count %d" % s.count(old))
    s = s.replace(old, new)
open(p, "w").write(s)
PY
  then fail "M-$name: mutation did not land"; return; fi
  if cmp -s "$WF" "$T/m.yml"; then fail "M-$name: mutation did not change the file"; return; fi
  out="$(python3 "$T/check.py" "$T/m.yml")"
  case "$out" in
    FAIL*"$want"*) pass "M-$name: FAIL ($want)" ;;
    *) fail "M-$name: checker did not fail for its named reason" "want [$want] got [$out]" ;;
  esac
}
# Positive control for the verdict helper (review #9453): `row` must be able to FAIL. Driven once with a
# mutation the checker really catches ("mint:repositories") but a reason it never names, in a subshell so the
# counters roll back; it must record exactly one failure. printf + exit, never through fail().
# The output is captured and must carry the verdict's own text: an anchor that drifted records "mutation did not
# land" instead, which a bare count cannot tell from the verdict failing.
_rwo="$( (row st-must-reject "no-such-reason" "repositories: soleur-marketplace" "repositories: soleur,soleur-marketplace" 2>&1; printf '\n@@%s' "$fails") )"
_rw="${_rwo##*@@}"
if [[ "$_rw" != "$((fails + 1))" ]] || ! grep -qF 'M-st-must-reject: checker did not fail for its named reason' <<<"$_rwo"; then
  printf 'FAIL INSTRUMENT: row did not reject a mutation whose named reason is absent, for its named reason (fails %s -> %s)\n' "$fails" "$_rw" >&2; exit 1
fi
row widen-permissions  "mint:permissions"     "permissions: '{\"administration\":\"write\"}'" "permissions: '{\"administration\":\"write\",\"secrets\":\"write\"}'"
# Dropping the explicit source would default the call to the narrow project, which the
# broad token cannot read: every infra/github apply would stop at this mint step.
row project-dropped    "mint:doppler-project" "          doppler-project: soleur-infra-privileged
" ""
row widen-repositories "mint:repositories"    "repositories: soleur-marketplace" "repositories: soleur,soleur-marketplace"
row tier-a-token       "mint:doppler-token"   "doppler-token: \${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}" "doppler-token: \${{ secrets.DOPPLER_TOKEN }}"
row tolerated-mint     "mint:may-be-skipped"  "        id: mint
" "        id: mint
        continue-on-error: true
"
row revoke-loosened    "revoke:condition"     "if: always() && steps.mint.outcome == 'success'" "if: success()"
# The token reaching a THIRD step (here the manifest verifier, which needs none).
row env-token-leak     "token:holders"        "          RAW_URL: https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json
" "          RAW_URL: https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json
          EXTRA_TOKEN: \${{ steps.mint.outputs.token }}
"
row job-not-tier-b     "env:job-not-infra-privileged" "    environment: infra-privileged
" "    environment: infra-unprivileged
"

# --- Guard 2 rows (#9362): no Tier-A value reaches Terraform, and the by-value gate cannot be dropped ---
WRAP='doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
'
row g2-wrapper-apply     "g2:wrapper"          'terraform apply -auto-approve -input=false tfplan 2>&1 | tee' "${WRAP}            terraform apply -auto-approve -input=false tfplan 2>&1 | tee"
# Only the SECOND import helper regressed: the first stays compliant, so a "first match" checker passes it.
row g2-wrapper-import-2  "g2:wrapper"          'terraform import "$addr" "$name"' "${WRAP}                terraform import \"\$addr\" \"\$name\""
row g2-token-plan        "g2:doppler-token-env" '          HEAD_MSG: ${{ github.event.head_commit.message }}
        run: |
          # We capture' '          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
          HEAD_MSG: ${{ github.event.head_commit.message }}
        run: |
          # We capture'
row g2-token-verify-secrets "g2:doppler-token-env" "DOPPLER_TOKEN_CHECK: \${{ secrets.DOPPLER_TOKEN }}" "DOPPLER_TOKEN: \${{ secrets.DOPPLER_TOKEN }}"
row g2-secrets-download  "g2:secrets-download" "      - name: Terraform init
" '      - name: Pull tier-A values
        run: doppler secrets download --no-file --format env >> "$GITHUB_ENV"
      - name: Terraform init
'
row g2-no-apply-job      "g2:no-steps"         "
  apply:
    environment: infra-privileged" "
  applyx:
    environment: infra-privileged"
row g2-gate-removed      "g2:gate-missing"     "Gate planned required-check bindings (by value, pre-apply)" "Some other step"
# Moved after apply: cut the gate step (with its comment block) and re-insert it after the apply step.
python3 - "$WF" "$T/m.yml" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index("      # A pre-apply by-value gate on the two rulesets")
b = s.index("      - name: Terraform apply\n")
c = s.index("      - name: Post-apply verify (ruleset required check counts")
gate = s[a:b]
open(sys.argv[2], "w").write(s[:a] + s[b:c] + gate + s[c:])
PY
out="$(python3 "$T/check.py" "$T/m.yml")"
case "$out" in
  FAIL*"g2:gate-order"*) pass "M-g2-gate-after-apply: FAIL (g2:gate-order)" ;;
  *) fail "M-g2-gate-after-apply: checker did not fail for its named reason" "want [g2:gate-order] got [$out]" ;;
esac
row g2-gate-wrong-address "g2:gate-address-canonical-map" '            - github_repository_ruleset.cla_required \' '            - github_repository_ruleset.ci_required \'
row g2-gate-one-invocation "g2:gate-invocations" '          terraform show -json tfplan | bash "${GITHUB_WORKSPACE}/scripts/verify-ruleset-required-checks.sh" \
            - github_repository_ruleset.cla_required \
            "${GITHUB_WORKSPACE}/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
' ''
row g2-gate-relative-path "g2:gate-path-or-shape" 'bash "${GITHUB_WORKSPACE}/scripts/verify-ruleset-required-checks.sh" \
            - github_repository_ruleset.ci_required' 'bash "scripts/verify-ruleset-required-checks.sh" \
            - github_repository_ruleset.ci_required'
row g2-gate-no-pipefail  "g2:gate-pipefail"    "set -euo pipefail
          # Pre-apply by-value gate" "set -eu
          # Pre-apply by-value gate"
# Must-PASS: a harmless comment added to the real workflow leaves every pin satisfied.
cp "$WF" "$T/m.yml"; printf '\n# harmless trailing comment\n' >> "$T/m.yml"
out="$(python3 "$T/check.py" "$T/m.yml")"
if [[ "$out" == "PASS" ]]; then pass "P-harmless-comment: a comment-only edit still passes every pin"
else fail "P-harmless-comment: a comment-only edit fails a pin" "$out"; fi

# --- Guard 1 (#9362): scripts/verify-ruleset-required-checks.sh, driven over plans built at run time ---
GATE_SH="$REPO_ROOT/scripts/verify-ruleset-required-checks.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures/tfplan-real-ruleset-baseline.json"
CI_CAN="$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json"
CLA_CAN="$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
CI_ADDR=github_repository_ruleset.ci_required
CLA_ADDR=github_repository_ruleset.cla_required
mkplan() { # <out> <addr> <canonical> [jq filter over the required_check array] [action]
  local out="$1" addr="$2" can="$3" edit="${4:-.}" action="${5:-update}"
  jq --arg addr "$addr" --arg action "$action" --slurpfile can "$can" "
    .resource_changes[0] as \$rc
    | .resource_changes = [\$rc
        | .address = \$addr
        | .change.actions = [\$action]
        | .change.after.rules[0].required_status_checks[0].required_check = (\$can[0] | $edit)]" "$FIX" > "$out"
}
# A gate-rows run reports its own tally; it never touches the suite's ledger, so a stub run can be scored.
gate_rows() { # <script>  -> prints "ok|FAIL <name>" lines
  local sh="$1" d; d="$(mktemp -d "$T/gate.XXXXXX")"
  chk() { # <name> <want rc> <script args...>   (stdin from $d/in)
    local name="$1" want="$2" rc=0; shift 2
    bash "$sh" "$@" < "$d/in" > "$d/out" 2>&1 || rc=$?
    if [[ "$rc" == "$want" ]]; then echo "ok $name"; else echo "FAIL $name (want rc=$want got rc=$rc)"; fi
  }
  local cfg addr can
  for cfg in "ci|$CI_ADDR|$CI_CAN" "cla|$CLA_ADDR|$CLA_CAN"; do
    IFS='|' read -r cfg addr can <<<"$cfg"
    mkplan "$d/in" "$addr" "$can" "." update;                 chk "$cfg: canonical as-is (update) passes" 0 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "reverse" update;           chk "$cfg: rows reordered pass" 0 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "map(. + {extra:\"x\"})" update; chk "$cfg: extra provider fields pass" 0 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "." no-op;                  chk "$cfg: no-op plan equal to canonical passes" 0 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ".[0].integration_id = 57789" update;  chk "$cfg: FIRST row rebound is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ".[-1].integration_id = 57789" update; chk "$cfg: LAST row rebound is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ".[0].context = \"renamed\"" update;   chk "$cfg: a context renamed is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "del(.[0])" update;         chk "$cfg: a context dropped is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ". + [{context:\"extra\",integration_id:15368}]" update; chk "$cfg: a context added is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ".[0].integration_id = null" update;   chk "$cfg: a null integration_id is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" ".[0].integration_id = 57789" no-op;   chk "$cfg: a rebound under a no-op action is RED" 1 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "[]" update;                chk "$cfg: an empty required set is exit 2" 2 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "." update;                 chk "$cfg: an absent address is exit 2" 2 - github_repository_ruleset.nope "$can"
    mkplan "$d/in" "$addr" "$can" "." update; jq '.resource_changes[0].change.after = null | .resource_changes[0].change.actions = ["delete"]' "$d/in" > "$d/in2"; mv "$d/in2" "$d/in"
    chk "$cfg: a delete (after null) is exit 2" 2 - "$addr" "$can"
    mkplan "$d/in" "$addr" "$can" "." update
    printf '[]' > "$d/can"; chk "$cfg: an empty canonical is exit 2" 2 - "$addr" "$d/can"
    printf '{}' > "$d/can"; chk "$cfg: a non-array canonical is exit 2" 2 - "$addr" "$d/can"
    jq '. + [.[0]]' "$can" > "$d/can"; chk "$cfg: a duplicate-context canonical is exit 2" 2 - "$addr" "$d/can"
    jq '.[0].integration_id = "15368"' "$can" > "$d/can"; chk "$cfg: a string-id canonical is exit 2" 2 - "$addr" "$d/can"
  done
  : > "$d/in"; chk "empty stdin is exit 2" 2 - "$CI_ADDR" "$CI_CAN"
  chk "no arguments is exit 2" 2
}
echo "--- Guard 1: by-value gate script"
if [[ ! -f "$GATE_SH" ]]; then
  fail "G1: scripts/verify-ruleset-required-checks.sh exists"
else
  _g1="$(gate_rows "$GATE_SH")"
  while IFS= read -r line; do
    case "$line" in
      "ok "*)   pass "G1: ${line#ok }" ;;
      "FAIL "*) fail "G1: ${line#FAIL }" ;;
    esac
  done <<<"$_g1"
  [[ -n "$_g1" ]] || fail "G1: the gate rows ran" "no rows printed"
  # Harness row: a stub that always exits 0 must turn the same rows RED (the rows can fail).
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/stub.sh"
  _stub="$(gate_rows "$T/stub.sh" | grep -c '^FAIL ' || true)"
  if [[ "$_stub" -gt 0 ]]; then pass "H-gate-stub: an always-exit-0 script fails $_stub gate rows"
  else fail "H-gate-stub: an always-exit-0 script passed every gate row (the rows cannot fail)"; fi
fi

# Floors (printf + exit, never through fail()): the control, the mutation rows, Guard 2 and Guard 1.
MIN_ASSERTIONS=61
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran, floor is %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2; exit 1
fi
if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== apply-github-infra-mint-shape: %d passed, %d failed ===\n' "$passes" "$fails"
exit $(( ${#FAILURES[@]} > 0 ))
