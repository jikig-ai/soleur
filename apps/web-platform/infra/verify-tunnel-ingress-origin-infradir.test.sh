#!/usr/bin/env bash
# Regression guard for #6595: verify-tunnel-ingress-origin.sh must resolve its
# infra dir from its OWN location (absolute, CWD-independent), NOT by `cd`-ing a
# possibly-relative $INFRA_DIR env var.
#
# The post-merge apply of PR #6595 died here:
#   verify-tunnel-ingress-origin.sh: line 18: cd: apps/web-platform/infra: No such file or directory
# because apply-web-platform-infra.yml exports INFRA_DIR=apps/web-platform/infra
# (relative) AND runs the step with working-directory=$INFRA_DIR — so the CWD is
# ALREADY the infra dir, and `cd apps/web-platform/infra` from inside it fails.
# That failure is not cosmetic: the verify step gates the SSH-provisioned apply
# leg (`if: success()`), so it skipped the apply that delivers the fail2ban
# `ignoreip` grant and every other SSH-provisioned resource fleet-wide.
#
# This test reproduces the CI invocation exactly (CWD = infra dir, INFRA_DIR set
# to the relative value) with a stub `doppler` on PATH, and asserts the script
# gets PAST the `cd` — i.e. it reaches its first external call instead of dying
# on a path that does not exist. Hermetic: no network, no doppler, no prod.

set -euo pipefail

echo "verify-tunnel-ingress-origin-infradir.test.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ABS="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$INFRA_ABS/scripts/verify-tunnel-ingress-origin.sh"
# The relative value the workflow exports (env.INFRA_DIR at line 128).
REL_INFRA_DIR="apps/web-platform/infra"

[[ -f "$TARGET" ]] || { echo "FAIL: $TARGET not found"; exit 1; }

fails=0

# --- Stub PATH: a fake `doppler` that records it was reached, then exits. -----------
# doppler is the FIRST external command the script runs after the cd, so reaching
# it proves the cd resolved. It exits 0 with no output; the script then fails its
# own IP-regex check and exits 1 — expected, and irrelevant to this test.
STUB_DIR="$(mktemp -d)"
# MARKER lives inside the unique STUB_DIR and is created ONLY by the stub's
# `touch` below — so the `-e` check on it is the stub-hit observable. Creating
# it up front (plain `mktemp`) would make that arm vacuous: the file would
# exist whether or not the script ever reached doppler.
MARKER="$STUB_DIR/marker"
trap 'rm -rf "$STUB_DIR"' EXIT
cat >"$STUB_DIR/doppler" <<STUB
#!/usr/bin/env bash
touch "$MARKER"
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# --- Reproduce the CI invocation: CWD = absolute infra dir, INFRA_DIR = relative. ---
set +e
OUT="$(cd "$INFRA_ABS" && INFRA_DIR="$REL_INFRA_DIR" PATH="$STUB_DIR:$PATH" \
  bash "$TARGET" 2>&1)"
set -e

if printf '%s' "$OUT" | grep -ciE 'cd:.*No such file or directory' >/dev/null; then
  echo "FAIL: script died on the relative-INFRA_DIR cd — #6595 regression:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
  fails=1
elif [[ ! -e "$MARKER" ]]; then
  echo "FAIL: script never reached its first external call (doppler stub not hit) — it did not get past the cd:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
  fails=1
else
  echo "PASS: script resolves the infra dir absolutely and reaches its first call with CWD=infra-dir + relative INFRA_DIR"
fi

# --- Also assert the source no longer honors a relative $INFRA_DIR override. --------
# A structural belt to the behavioral test above: the resolution must not be
# `${INFRA_DIR:-...}` (which re-admits the relative env value). It must derive from
# BASH_SOURCE unconditionally.
if grep -qE 'INFRA_DIR="\$\{INFRA_DIR:-' "$TARGET"; then
  echo "FAIL: script still honors a relative \$INFRA_DIR override (\${INFRA_DIR:-...}) — the #6595 bug can recur"
  fails=1
else
  echo "PASS: infra dir is derived from BASH_SOURCE, not a relative env override"
fi

# --- Self-registration: presence under infra/ is registration since #8736, so
# what this suite pins is the CONNECTION — the legs' runner invocation. --------
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"
if [[ -f "$INFRA_VALIDATION" ]] && \
   grep -qE 'run: bash apps/web-platform/infra/run-registered-suites\.sh' "$INFRA_VALIDATION"; then
  echo "PASS: the suite runner is invoked in infra-validation.yml"
else
  echo "FAIL: the suite runner is NOT invoked in infra-validation.yml — no infra suite would run in CI (#5417 class)"
  fails=1
fi

# ─── #12937 Guard 3: the verify reads the tunnel the `_soleur` CNAMEs point at, and checks all three routes ───────────
# Hermetic: stub doppler / terraform / curl / sleep on PATH, synthesized Cloudflare bodies, no network. The stubs log
# every curl URL so a row can assert WHICH account and tunnel the script read (behavior, not a source grep).
# The stubs read their answers with `printenv`, never a bash name indirection: test-trio-baseline-census.sh
# treats an indirection as a credential READ SHAPE, and this file only sets the deploy trio for the script.
G3="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR" "$G3"' EXIT
mkdir -p "$G3/bin"
cat >"$G3/bin/doppler" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  run) while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift; exec "$@" ;;
  secrets) val="$(printenv "STUB_DOPPLER_$3")" && [[ -n "$val" ]] || exit 1; printf '%s' "$val" ;;
  *) exit 1 ;;
esac
STUB
cat >"$G3/bin/terraform" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  console) cat >/dev/null; printf '"%s"\n"%s"\n' "$STUB_WEB1_IP" "$STUB_REG_EP" ;;
  output) val="$(printenv "STUB_TFOUT_$3")" && [[ -n "$val" ]] || exit 1; printf '%s' "$val" ;;
  state) printf '  id = "%s"\n' "$STUB_STATE_TUNNEL_ID" ;;
  *) exit 1 ;;
esac
STUB
cat >"$G3/bin/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
url=""; out=""; prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
printf '%s\n' "$url" >>"$STUB_CURL_LOG"
case "$url" in
  */configurations) cat "$STUB_CFG_FILE" ;;
  */connections)
    [[ "$url" == "https://api.cloudflare.com/client/v4/${STUB_CONN_PATH}" ]] || { printf '%s\n' "$url" >>"$STUB_REFUSED_LOG"; exit 64; }
    cat "$STUB_CONN_FILE"; printf '\n%s' "$STUB_CONN_CODE" ;;
  */hooks/deploy-status) [[ -n "$out" ]] && printf '{"host_id":"stub-host"}' >"$out"; printf '%s' "$STUB_DEPLOY_CODE" ;;
  *) exit 7 ;;
esac
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$G3/bin/sleep"
chmod +x "$G3/bin/"*

NEW_ACCT="66d4f93f7397f196544e9fe84c3557c2"; OLD_ACCT="0123456789abcdef0123456789abcdef"
NEW_TUN="11111111-2222-4333-8444-555555555555"; OLD_TUN="99999999-8888-4777-8666-555555555555"
# cfg <registry-service> [extra-rule-json] -> a synthesized /configurations body
cfg() {
  jq -nc --arg reg "$1" --argjson extra "${2:-[]}" '{success: true, result: {config: {ingress: ([
    {hostname: "deploy.soleur.ai", service: "http://10.0.1.12:9000"},
    {hostname: "ssh.soleur.ai", service: "ssh://10.0.1.12:22"},
    {hostname: "registry.soleur.ai", service: $reg}] + $extra + [{service: "http_status:404"}])}}}' >"$G3/cfg.json"
}
conns() { jq -nc --argjson n "$1" '{success: true, result: ([range($n)] | map({id: "c\(.)aaaaaaaa", conns: [{colo_name: "hel01", client_version: "2026.10.4"}]}))}' >"$G3/conns.json"; }
# g3run [script] -> runs the verify with the stubs; leaves rc in G3RC, stdout+stderr in $G3/out, curl URLs in $G3/curl.log
g3run() {
  : >"$G3/curl.log"; : >"$G3/refused.log"; : >"$G3/gh_output"; : >"$G3/gh_summary"
  set +e
  ( cd "$INFRA_ABS" && env PATH="$G3/bin:$PATH" STUB_CURL_LOG="$G3/curl.log" STUB_REFUSED_LOG="$G3/refused.log" STUB_CONN_PATH="$CONN_URL" STUB_CFG_FILE="$G3/cfg.json" \
      STUB_CONN_FILE="$G3/conns.json" STUB_CONN_CODE="${G3_CONN_CODE:-200}" STUB_DEPLOY_CODE="${G3_DEPLOY_CODE:-200}" \
      STUB_WEB1_IP="10.0.1.12" STUB_REG_EP="10.0.1.30:5000" STUB_STATE_TUNNEL_ID="$OLD_TUN" \
      STUB_TFOUT_cf_tunnel_id="${G3_TFOUT_TUN-$NEW_TUN}" STUB_TFOUT_cf_tunnel_account_id="${G3_TFOUT_ACCT-$NEW_ACCT}" \
      STUB_DOPPLER_CF_API_TOKEN="stubtoken123" STUB_DOPPLER_CF_ACCOUNT_ID="$OLD_ACCT" STUB_DOPPLER_APP_DOMAIN_BASE="soleur.ai" \
      WEBHOOK_DEPLOY_SECRET="whsec" CF_ACCESS_CLIENT_ID="id.access" CF_ACCESS_CLIENT_SECRET="sec" \
      GITHUB_OUTPUT="$G3/gh_output" GITHUB_STEP_SUMMARY="$G3/gh_summary" \
      bash "${1:-$TARGET}" >"$G3/out" 2>&1 )
  G3RC=$?
  set -e
}
g3pass() { echo "PASS: $1"; }
g3fail() { echo "FAIL: $1"; sed 's/^/    /' "$G3/out" | tail -8; fails=1; }
g3rows=0
g3row() { g3rows=$((g3rows + 1)); if eval "$2"; then g3pass "$1"; else g3fail "$1"; fi; }
# Self-test, exiting directly: a neutered g3fail/g3row that never moves the fail flag would turn every row green.
( fails=0; g3fail "self-test" >/dev/null 2>&1; [[ "$fails" -eq 1 ]] ) || { printf 'FAIL: g3fail does not set the fail flag\n'; exit 1; }
( fails=0; g3row "self-test" false >/dev/null 2>&1; [[ "$fails" -eq 1 ]] ) || { printf 'FAIL: a false g3row predicate does not set the fail flag\n'; exit 1; }
CFG_URL="accounts/${NEW_ACCT}/cfd_tunnel/${NEW_TUN}/configurations"
CONN_URL="accounts/${NEW_ACCT}/cfd_tunnel/${NEW_TUN}/connections"
# The must-PASS predicate, reused by the mutation rows: green AND the read went to the TF-output account + tunnel.
p_reads_soleur_tunnel() { if [[ "$G3RC" -eq 0 ]] && grep -qF "$CFG_URL" "$G3/curl.log"; then return 0; fi; return 1; }

# Must-PASS: all three correct rules + the catch-all, deploy-status 200.
cfg "tcp://10.0.1.30:5000"; conns 1
g3run
g3row "G3 must-PASS: three origin-relative rules + catch-all verify green, read from the TF-output account and tunnel" p_reads_soleur_tunnel
g3row "G3 row 1/4: the read never names the old account or the old state-address tunnel" '! grep -qE "${OLD_ACCT}|${OLD_TUN}" "$G3/curl.log"'
cfg "http://10.0.1.30:5000"; g3run
g3row "G3 row 2: a registry. rule rewritten to http:// reds, naming registry." '[[ "$G3RC" -ne 0 ]] && grep -qF "live registry. ingress service is" "$G3/out"'
cfg "tcp://10.0.1.30:5000" '[{"hostname":"registry.soleur.ai","service":"tcp://10.0.1.31:5000"}]'; g3run
g3row "G3 row 3: a second registry. rule after a compliant first reds (every matching rule is checked)" '[[ "$G3RC" -ne 0 ]] && grep -qF "live registry. ingress service is" "$G3/out"'
cfg "tcp://10.0.1.30:5000" '[{"hostname":"registry.soleur.ai","service":"tcp://localhost:5000"}]'; g3run
g3row "G3 row 3b: ... and a second localhost: registry. rule reds too" '[[ "$G3RC" -ne 0 ]]'
cfg "tcp://10.0.1.30:5000"
G3_TFOUT_TUN="" g3run
g3row "G3 harness: an EMPTY terraform output for cf_tunnel_id reds (never a skip)" '[[ "$G3RC" -ne 0 ]] && grep -qF "terraform output cf_tunnel_id" "$G3/out" && ! grep -q . "$G3/curl.log"'
G3_TFOUT_ACCT="" g3run
g3row "G3 harness: an EMPTY terraform output for cf_tunnel_account_id reds (never a skip)" '[[ "$G3RC" -ne 0 ]] && grep -qF "terraform output cf_tunnel_account_id" "$G3/out"'

# 1.9: the data plane fails -> SOLEUR_TUNNEL_VERIFY names the measured cause, and the script STILL exits non-zero.
# T1's must-hold predicate (reused by MG3-T1c): red, the no-connector line, and the census read went to the TF-output account + tunnel.
p_t1() {
  if [[ "$G3RC" -ne 0 ]] && grep -qxF "SOLEUR_TUNNEL_VERIFY cause=no-connector tunnel=${NEW_TUN} connections=0" "$G3/out" \
     && grep -qF "$CONN_URL" "$G3/curl.log" && ! grep -q . "$G3/refused.log"; then return 0; fi
  return 1
}
conns 0; G3_DEPLOY_CODE=530 g3run
g3row "T1: 0 connectors -> 'SOLEUR_TUNNEL_VERIFY cause=no-connector tunnel=<id> connections=0', a non-zero exit, census read from the TF-output account + tunnel" p_t1
g3row "T1c: ... the annotation carries the web-2 rebake remedy and never blames the origin or prescribes the pin revert" \
  'grep -qF "::error::SOLEUR_TUNNEL_VERIFY cause=no-connector" "$G3/out" && grep -qF "web_host_key=web-2" "$G3/out" && ! grep -qF "management plane is down" "$G3/out" && ! grep -qF "revert the ingress pin" "$G3/out"'
g3row "T1b: ... the cause reaches GITHUB_OUTPUT (the failure email reads it) and the step summary explains it" \
  'grep -qxF "cause=no-connector" "$G3/gh_output" && grep -qF "no connector" "$G3/gh_summary"'
conns 1; G3_DEPLOY_CODE=502 g3run
g3row "T2: a live connector but a dead origin -> cause=origin-not-serving connections=1, non-zero exit" \
  '[[ "$G3RC" -ne 0 ]] && grep -qxF "SOLEUR_TUNNEL_VERIFY cause=origin-not-serving tunnel=${NEW_TUN} connections=1" "$G3/out" && ! grep -q . "$G3/gh_summary"'
g3row "T2b: ... and only origin-not-serving prints the origin-down annotation and the pin-revert recovery" \
  'grep -qF "management plane is down" "$G3/out" && grep -qF "revert the ingress pin" "$G3/out"'
G3_DEPLOY_CODE=403 g3run
g3row "T4: a live connector and an Access 403 -> cause=access-refused (not an origin fault), non-zero exit" \
  '[[ "$G3RC" -ne 0 ]] && grep -qxF "SOLEUR_TUNNEL_VERIFY cause=access-refused tunnel=${NEW_TUN} connections=1" "$G3/out" && grep -qxF "cause=access-refused" "$G3/gh_output" && ! grep -qF "management plane is down" "$G3/out"'
G3_DEPLOY_CODE=000 G3_CONN_CODE=500 g3run
g3row "T3: an unreadable connection count -> cause=connections-unreadable (never a zero), non-zero exit" \
  '[[ "$G3RC" -ne 0 ]] && grep -qxF "SOLEUR_TUNNEL_VERIFY cause=connections-unreadable tunnel=${NEW_TUN} connections=unknown" "$G3/out"'
g3row "T3b: ... says nothing was measured, and never blames the origin" \
  'grep -qF "neither the connector nor the origin was measured" "$G3/out" && ! grep -qF "management plane is down" "$G3/out"'
conns 1

# Mutation proof: each Guard 3 row reds when its guard is removed. The mutant runs from a mirror of the repo layout
# (the script resolves its infra dir from its own location and sources ../../../scripts/ on the failure path).
mkdir -p "$G3/tree/apps/web-platform/infra/scripts" "$G3/tree/scripts"
cp "$REPO_ROOT/scripts/tunnel-connector-census.sh" "$G3/tree/scripts/"
g3mut() { # <name> <python-snippet editing s> -> $G3/tree/apps/web-platform/infra/scripts/<name>.sh
  python3 - "$TARGET" "$G3/tree/apps/web-platform/infra/scripts/$1.sh" "$2" <<'PY'
import sys
s = open(sys.argv[1]).read(); old = s
exec(sys.argv[3])
assert s != old, "mutation did not land"
open(sys.argv[2], "w").write(s)
PY
}
MUT="$G3/tree/apps/web-platform/infra/scripts"
g3mut m_state 's = s.replace("TUNNEL_ID=$(terraform output -raw cf_tunnel_id 2>/dev/null || true)", "TUNNEL_ID=$(terraform state show cloudflare_zero_trust_tunnel_cloudflared.web 2>/dev/null | awk \x27/^[[:space:]]*id[[:space:]]*=/ { gsub(/\"/, \"\", $3); print $3; exit }\x27)", 1)' || fails=1
cfg "tcp://10.0.1.30:5000"; g3run "$MUT/m_state.sh"
g3row "MG3-1: a script reading the OLD state address fails the must-PASS predicate" '! p_reads_soleur_tunnel'
# The two "reads Doppler CF_ACCOUNT_ID again" mutants substitute the stub Doppler VALUE (the old account) rather
# than a literal Doppler command, so this test file carries no credential read shape for the trio census to key on.
g3mut m_doppler 's = s.replace("TUNNEL_ACCOUNT_ID=$(terraform output -raw cf_tunnel_account_id 2>/dev/null || true)", "TUNNEL_ACCOUNT_ID=$(printenv STUB_DOPPLER_CF_ACCOUNT_ID)", 1)' || fails=1
g3run "$MUT/m_doppler.sh"
g3row "MG3-4: a script reading the account from Doppler CF_ACCOUNT_ID again fails the must-PASS predicate" '! p_reads_soleur_tunnel'
g3mut m_noreg 's = s.replace(" \"registry|tcp://${REGISTRY_ENDPOINT}\"; do", "; do", 1).replace("[[ \"$n_checked\" -eq 3 ]]", "[[ \"$n_checked\" -eq 2 ]]", 1)' || fails=1
cfg "http://10.0.1.30:5000"; g3run "$MUT/m_noreg.sh"
g3row "MG3-2: without the registry. pair, row 2's http:// registry rule would verify GREEN (row 2 depends on it)" '[[ "$G3RC" -eq 0 ]]'
g3mut m_skip0 's = s.replace("  # Each cause gets its own annotation;", "  [[ \"$VERIFY_CAUSE\" == \"no-connector\" ]] \x26\x26 exit 0\n  # Each cause gets its own annotation;", 1)' || fails=1
cfg "tcp://10.0.1.30:5000"; conns 0; G3_DEPLOY_CODE=530 g3run "$MUT/m_skip0.sh"
g3row "MG3-T1: a green skip at zero connectors (the rejected advisor fork) fails T1's non-zero-exit predicate" '[[ "$G3RC" -eq 0 ]]'
g3mut m_oldconn 's = s.replace("accounts/${TUNNEL_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/connections", "accounts/$(printenv STUB_DOPPLER_CF_ACCOUNT_ID)/cfd_tunnel/${TUNNEL_ID}/connections", 1)' || fails=1
conns 0; G3_DEPLOY_CODE=530 g3run "$MUT/m_oldconn.sh"
g3row "MG3-T1c: a census read pointed at the old account fails T1's predicate (the stub refuses it)" '! p_t1 && grep -qF "$OLD_ACCT" "$G3/refused.log"'
conns 1
# An unknown census verdict must read as unmeasured. A census lib whose classifier answers a verdict the script does not know:
mkdir -p "$G3/fv/apps/web-platform/infra/scripts" "$G3/fv/scripts"
printf 'classify_connector_census() { echo "future_verdict 2"; }\n' >"$G3/fv/scripts/tunnel-connector-census.sh"
cp "$TARGET" "$G3/fv/apps/web-platform/infra/scripts/v.sh"
G3_DEPLOY_CODE=502 g3run "$G3/fv/apps/web-platform/infra/scripts/v.sh"
g3row "T5: an unknown census verdict -> cause=connections-unreadable connections=unknown (never origin-not-serving)" \
  '[[ "$G3RC" -ne 0 ]] && grep -qxF "SOLEUR_TUNNEL_VERIFY cause=connections-unreadable tunnel=${NEW_TUN} connections=unknown" "$G3/out"'

# Floor, exiting directly (not through g3fail): rows that silently stop running must not read as green.
G3_FLOOR=21
[[ "$g3rows" -ge "$G3_FLOOR" ]] || { printf 'FAIL: only %s Guard 3 rows ran (floor %s)\n' "$g3rows" "$G3_FLOOR"; exit 1; }
[[ "$fails" -eq 0 ]] || exit 1
echo "OK"
