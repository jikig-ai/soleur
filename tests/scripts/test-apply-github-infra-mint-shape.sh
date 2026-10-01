#!/usr/bin/env bash
# =============================================================================
# Shape pins for apply-github-infra.yml::apply's soleur-infra App token (#9360).
#
# The two older consumers of .github/actions/mint-infra-app-token carry shape rows
# (test-bump-inngest-bootstrap-pin.sh S16/S18/S19/S24, test-mint-inngest-bootstrap-tag.sh
# w12-w16); the third consumer gets the same here. The PROPERTY: the job is Tier B; it
# mints exactly one token, from the Tier-B secret, scoped exactly as declared, before any
# Terraform or Doppler-run step, failing the job if the mint fails; the token reaches only
# the verify step and the revoke step, through env:, never $GITHUB_ENV or ${{ }} in run:;
# and the last step revokes it on every path where the mint succeeded.
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
print("PASS" if not bad else "FAIL " + " ".join(bad))
PY

echo "--- control (the real workflow)"
ctl="$(python3 "$T/check.py" "$WF")"
if [[ "$ctl" == "PASS" ]]; then pass "C0: apply-github-infra.yml::apply holds every shape pin"
else fail "C0: the real workflow fails a shape pin" "$ctl"; fi

echo "--- mutations (each must FAIL for its named reason)"
row() { # <name> <expected reason substring> <python replace: old> <new>
  local name="$1" want="$2" out
  cp "$WF" "$T/m.yml"
  if ! python3 - "$T/m.yml" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    sys.exit("anchor count %d" % s.count(old))
open(p, "w").write(s.replace(old, new))
PY
  then fail "M-$name: mutation did not land"; return; fi
  if cmp -s "$WF" "$T/m.yml"; then fail "M-$name: mutation did not change the file"; return; fi
  out="$(python3 "$T/check.py" "$T/m.yml")"
  case "$out" in
    FAIL*"$want"*) pass "M-$name: FAIL ($want)" ;;
    *) fail "M-$name: checker did not fail for its named reason" "want [$want] got [$out]" ;;
  esac
}
row widen-permissions  "mint:permissions"     "permissions: '{\"administration\":\"write\"}'" "permissions: '{\"administration\":\"write\",\"secrets\":\"write\"}'"
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

# Floors (printf + exit, never through fail()): one control + seven mutation rows.
MIN_ASSERTIONS=8
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran, floor is %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2; exit 1
fi
if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== apply-github-infra-mint-shape: %d passed, %d failed ===\n' "$passes" "$fails"
exit $(( ${#FAILURES[@]} > 0 ))
