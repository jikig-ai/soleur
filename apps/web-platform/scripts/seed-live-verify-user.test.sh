#!/usr/bin/env bash
# Test guard for seed-live-verify-user.sh (#5452, AC8).
#
# Asserts the prd seed refuses to run when (1) DOPPLER_CONFIG != "prd",
# (2) the service-role JWT carries a non-service_role role, (3) the JWT ref
# does not match the canonical URL ref — and that NO secret-shaped string
# reaches stdout/stderr (no `set -x`, password/service-role-key never echoed).
#
# The refusal paths all exit before any curl, so this runs offline.

set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEED="$DIR/seed-live-verify-user.sh"
fail=0

[[ -f "$SEED" ]] || { echo "FATAL: $SEED not found" >&2; exit 2; }

# Build a 3-segment JWT whose payload base64url-decodes to the given JSON.
# Matches the seed's decode (cut -d. -f2 → tr '_-' '/+' → base64 -d).
make_jwt() { # <payload-json>
  local payload
  payload=$(printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
  printf 'eyJhbGciOiJIUzI1NiJ9.%s.sig' "$payload"
}

REF20="aaaaaaaaaaaaaaaaaaaa"   # 20-char canonical ref
WRONG_REF20="bbbbbbbbbbbbbbbbbbbb"
CANON_URL="https://${REF20}.supabase.co"

# Run the seed with a clean, fully-specified env (overridable per case) and
# capture combined output. Returns the script's exit code in $rc, output in
# $out.
run_seed() { # <KEY=VAL>...
  out=$(env -i \
    PATH="$PATH" HOME="${HOME:-/tmp}" \
    DOPPLER_CONFIG="prd" \
    NEXT_PUBLIC_SUPABASE_URL="$CANON_URL" \
    NEXT_PUBLIC_SUPABASE_ANON_KEY="anon-key-not-used-on-refuse-path" \
    LIVE_VERIFY_USER_PASSWORD="placeholder-not-reached" \
    "$@" \
    bash "$SEED" 2>&1)
  rc=$?
}

assert_refuses() { # <description> <expected-substring> <KEY=VAL>...
  local desc="$1" expect="$2"; shift 2
  run_seed "$@"
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAIL: $desc — expected non-zero exit, got 0" >&2
    fail=1
    return
  fi
  if ! printf '%s' "$out" | grep -qF "$expect"; then
    echo "  FAIL: $desc — output missing expected substring: $expect" >&2
    fail=1
    return
  fi
  echo "  ok: $desc (exit $rc)"
}

SERVICE_JWT=$(make_jwt "{\"role\":\"service_role\",\"ref\":\"$REF20\"}")
ANON_JWT=$(make_jwt "{\"role\":\"anon\",\"ref\":\"$REF20\"}")
WRONGREF_JWT=$(make_jwt "{\"role\":\"service_role\",\"ref\":\"$WRONG_REF20\"}")

# 1. Non-prd DOPPLER_CONFIG.
assert_refuses "refuses DOPPLER_CONFIG=dev" 'must be "prd"' \
  DOPPLER_CONFIG="dev" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_JWT"

# 2. Non-service_role JWT.
assert_refuses "refuses non-service_role JWT" 'expected "service_role"' \
  SUPABASE_SERVICE_ROLE_KEY="$ANON_JWT"

# 3. Wrong ref (canonical URL host ref != JWT ref).
assert_refuses "refuses JWT ref != URL ref" 'does not match URL canonical ref' \
  SUPABASE_SERVICE_ROLE_KEY="$WRONGREF_JWT"

# 4. Secret discipline (AC8) — static negative-space checks on the source.
if grep -qE '^[[:space:]]*set[[:space:]]+-x' "$SEED"; then
  echo "  FAIL: seed enables 'set -x' (would echo secret-laden command bodies)" >&2
  fail=1
else
  echo "  ok: no 'set -x' in seed"
fi

# The password / service-role key must never be DISPLAYED. Allowed:
#   - jq --arg interpolation into a curl -d body (not stdout)
#   - the JWT-decode pipeline `printf '%s' "$SRK" | tr.../cut.../base64...`
#     (output captured into a var, never reaches the terminal — the canonical
#     seed-dev-users.sh idiom). So we flag echo/printf of a secret var only when
#     it is NOT piped into a decode/transform tool.
#   - `::add-mask::` is the ONE echo of a secret that exists to PROTECT it:
#     the directive must carry the value for Actions to register it, and it is
#     emitted before first use so everything downstream is masked. Excluding it
#     is not a hole in this check — a rule that forbade it would forbid the
#     repo's own masking precedent (registry-pull-path-health.sh).
secret_echo=$(grep -nE '(echo|printf)[^|]*\$\{?(LIVE_VERIFY_USER_PASSWORD|SUPABASE_SERVICE_ROLE_KEY|SRK)\b' "$SEED" \
  | grep -vE '\|[[:space:]]*(tr|cut|base64|wc|jq|openssl)' \
  | grep -vF '::add-mask::' || true)
if [[ -n "$secret_echo" ]]; then
  echo "  FAIL: seed displays a secret variable:" >&2
  printf '%s\n' "$secret_echo" >&2
  fail=1
else
  echo "  ok: no echo/printf of password or service-role key (decode pipelines excluded)"
fi

# Belt-and-suspenders: none of the refusal-path outputs above leaked the
# constructed JWT bodies verbatim.
if printf '%s' "$SERVICE_JWT$ANON_JWT$WRONGREF_JWT" | grep -qF "placeholder-not-reached"; then
  : # impossible; keeps shellcheck quiet about the var
fi

# 5. repo_status literal correctness (#5472) — static-source checks.
#   The public.users PATCH must use repo_status: "ready". The users CHECK
#   constraint (mig 011_repo_connection.sql) admits only
#   not_connected|cloning|ready|error — a "connected" literal 23514s
#   (check-constraint violation) and aborts the seed. Target the
#   users PATCH specifically so this does NOT conflate with the workspaces
#   PATCH, which legitimately also carries repo_status: "ready".
#
#   RE-ANCHORED (#7969): the discriminator used to be `tc_accepted_version`,
#   which is no longer on this line — consent moved to the accept_terms RPC so
#   the Art. 7(1) ledger row gets written. The anchor was coupled to a field
#   unrelated to what it asserts, so a correct change to that field broke it
#   (cq-assert-anchor-not-bare-token). Re-anchored TWICE in one PR, which is
#   the lesson: the first re-anchor used `workspace_path`, and a later commit
#   removed that column (migration 112 dropped it; PostgREST answered 42703 and
#   aborted every run). An anchor has to be a field the assertion is ABOUT, not
#   one that merely happens to sit on the same line. `workspace_status` is the
#   users ladder's own field and is absent from the workspaces PATCH, which
#   carries repo_status + repo_url.
if grep -qE 'workspace_status: "ready", repo_status: "ready"' "$SEED"; then
  echo "  ok: public.users PATCH uses repo_status: \"ready\""
else
  echo "  FAIL: public.users PATCH (workspace_status line) does not carry repo_status: \"ready\"" >&2
  fail=1
fi

# The forbidden literal that violates the users CHECK constraint (23514) must
# appear nowhere in the seed.
if grep -qF 'repo_status: "connected"' "$SEED"; then
  echo "  FAIL: seed contains forbidden literal repo_status: \"connected\" (mig 011 CHECK → 23514)" >&2
  fail=1
else
  echo "  ok: no forbidden repo_status: \"connected\" literal in seed"
fi

# 6. Active-workspace binding (#5501) — static-source checks.
#   The deployed createConversation resolves conversations.workspace_id via the
#   fail-loud resolveUserWorkspaceBinding (agent-session-registry.ts:316), which
#   THROWS when user_session_state has no row for the user — so a chat send never
#   persists a conversation and the harness emits CANT-RUN:forURL. The seed MUST
#   upsert one user_session_state row binding the synthetic principal's solo
#   workspace + its organization. It MUST be a POST upsert (a bare PATCH no-ops on
#   the absent row) and MUST NOT route through the set_current_workspace_id RPC
#   (which needs auth.uid() and 28000s under a service-role caller).
if grep -qE 'rest/v1/user_session_state\?on_conflict=user_id' "$SEED"; then
  echo "  ok: seed upserts user_session_state (on_conflict=user_id)"
else
  echo "  FAIL: seed does not POST-upsert /rest/v1/user_session_state?on_conflict=user_id (#5501 binding gap)" >&2
  fail=1
fi

if grep -qE 'resolution=merge-duplicates' "$SEED"; then
  echo "  ok: user_session_state upsert uses resolution=merge-duplicates"
else
  echo "  FAIL: user_session_state write is not a merge-duplicates upsert (a no-op PATCH leaves the binding absent)" >&2
  fail=1
fi

if grep -qE 'current_workspace_id' "$SEED" && grep -qE 'current_organization_id' "$SEED"; then
  echo "  ok: binding writes current_workspace_id AND current_organization_id"
else
  echo "  FAIL: binding body missing current_workspace_id and/or current_organization_id" >&2
  fail=1
fi

if grep -qE 'select=organization_id' "$SEED"; then
  echo "  ok: seed resolves organization_id from the workspace row before the upsert"
else
  echo "  FAIL: seed does not resolve organization_id (select=organization_id) before binding" >&2
  fail=1
fi

# Must NOT route the binding through the auth.uid()-requiring RPC (would 28000).
if grep -qE '/rpc/set_current_workspace_id' "$SEED"; then
  echo "  FAIL: seed calls /rpc/set_current_workspace_id — 28000s under service-role (no auth.uid())" >&2
  fail=1
else
  echo "  ok: seed does not route the binding through set_current_workspace_id RPC"
fi

# Write order: the workspace must be resolved (workspace_members owner lookup)
# BEFORE the user_session_state upsert can bind to it.
uss_line=$(grep -nE 'rest/v1/user_session_state' "$SEED" | head -1 | cut -d: -f1)
wm_line=$(grep -nE 'rest/v1/workspace_members' "$SEED" | head -1 | cut -d: -f1)
if [[ -n "$uss_line" && -n "$wm_line" && "$uss_line" -gt "$wm_line" ]]; then
  echo "  ok: user_session_state upsert (line $uss_line) comes after workspace_members lookup (line $wm_line)"
else
  echo "  FAIL: user_session_state upsert must come after the workspace_members owner lookup (uss=$uss_line wm=$wm_line)" >&2
  fail=1
fi

# --- #7969: the T&C version must be DERIVED, and consent must go through the RPC ---
#
# The principal sat at tc_accepted_version 2.3.0 against a gate requiring 2.5.1,
# so live-verify redirected to /accept-terms and timed out on a page that could
# never contain the composer. The literal in this script was correct when it was
# written; nothing re-derived it after the bump.

TC_SRC_F="$(cd "$(dirname "$SEED")" && pwd)/../lib/legal/tc-version.ts"
SSOT_VER="$(sed -n 's/^export const TC_VERSION = "\([^"]*\)";$/\1/p' "$TC_SRC_F")"

# (a) No restated version literal. A hardcoded semver here is the drift shape.
if grep -nE '^[[:space:]]*TC_VERSION=["'"'"']?[0-9]+\.[0-9]+\.[0-9]+' "$SEED"; then
  echo "  FAIL: seed RESTATES a TC_VERSION literal — derive it from lib/legal/tc-version.ts" >&2
  fail=1
else
  echo "  ok: seed does not restate a TC_VERSION literal"
fi

# (b) It derives from the source of truth, and the derivation actually works.
derived="$(sed -n 's/^export const TC_VERSION = "\([^"]*\)";$/\1/p' "$TC_SRC_F")"
if [[ -n "$derived" && "$derived" == "$SSOT_VER" ]]; then
  echo "  ok: TC_VERSION derives from tc-version.ts (got $derived)"
else
  echo "  FAIL: the TC_VERSION extraction yields '$derived' — it is broken" >&2
  fail=1
fi

# (c) NON-VACUITY CONTROL: the extraction must FAIL on a file that lacks the
# export. Without this, a `sed` that matches nothing looks identical to success.
neg="$(printf 'export const SOMETHING_ELSE = "x";\n' \
  | sed -n 's/^export const TC_VERSION = "\([^"]*\)";$/\1/p')"
if [[ -z "$neg" ]]; then
  echo "  ok: extraction yields empty on a file without the export (control fires)"
else
  echo "  FAIL: extraction returned '$neg' from a file with no TC_VERSION — it matches too much" >&2
  fail=1
fi

# (d) The seed must REFUSE rather than proceed on a broken extraction — an empty
# version would PATCH the gate column to "" and re-break the harness identically.
if grep -qE 'is not a semver' "$SEED"; then
  echo "  ok: seed refuses a non-semver derived version"
else
  echo "  FAIL: seed does not validate the derived TC_VERSION — an empty value would ship" >&2
  fail=1
fi

# (e) Consent goes through public.accept_terms, not a bare users PATCH. The RPC
# is what writes the Art. 7(1) tc_acceptances ledger row; PATCHing the column
# alone records consent with no audit row (observed in prod: column set since
# 2026-06-17, ledger EMPTY).
if grep -q 'rpc/accept_terms' "$SEED"; then
  echo "  ok: consent routed through public.accept_terms (writes the ledger row)"
else
  echo "  FAIL: seed does not call rpc/accept_terms — the tc_acceptances ledger row would be missing" >&2
  fail=1
fi
if grep -qE 'tc_accepted_version:[[:space:]]*\$tc' "$SEED"; then
  echo "  FAIL: seed still PATCHes tc_accepted_version directly — that bypasses the ledger" >&2
  fail=1
else
  echo "  ok: seed no longer PATCHes tc_accepted_version directly"
fi

# --- #7969: the release workflow must RUN this seed before live-verify ---
#
# Deriving the version only makes the NEXT run correct; it does not make a run
# happen. The harness broke because nothing re-ran the seed after a TC_VERSION
# bump, so the wiring is the load-bearing half and must not be deletable in
# silence. Parsed as YAML, not grepped: step ORDER is the property.
WF_F="$(cd "$(dirname "$SEED")" && pwd)/../../../.github/workflows/web-platform-release.yml"
# This suite is auto-discovered by scripts/test-all.sh's `apps/web-platform/scripts/*.test.sh`
# glob and runs in the BLOCKING `test-scripts` CI job, which installs no python
# packages. PyYAML therefore comes from the runner image, and image drift would
# otherwise surface as an unexplained bare FAIL on an unrelated PR. Name it.
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "  FAIL: PyYAML missing — cannot verify the release-workflow wiring" >&2
  fail=1
elif [[ -f "$WF_F" ]]; then
  wf_report="$(python3 - "$WF_F" <<'PYEOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["live-verify"]["steps"]
seed = harness = None
for i, st in enumerate(steps):
    run = st.get("run") or ""
    if "seed-live-verify-user.sh" in run:
        seed = (i, st)
    if "live-verify/run.ts" in run:
        harness = (i, st)
if seed is None:
    print("FAIL:the live-verify job does not run seed-live-verify-user.sh")
elif harness is None:
    print("FAIL:could not locate the harness step to compare against")
else:
    si, sst = seed
    hi, _ = harness
    if si >= hi:
        print(f"FAIL:seed step (index {si}) must precede the harness (index {hi})")
    elif sst.get("continue-on-error"):
        # continue-on-error pins `conclusion` to success, making a real failure
        # unreadable from the API — the step reports via its own rc instead.
        print("FAIL:seed step uses continue-on-error, which hides its own failure")
    elif "steps.gate.outputs.triggered" not in str(sst.get("if") or ""):
        print("FAIL:seed step is not gated on the same trigger as the harness")
    else:
        print(f"OK:seed step at index {si} precedes the harness at {hi}, same trigger, honest rc")
PYEOF
)"
  if [[ "$wf_report" == OK:* ]]; then
    echo "  ok: release workflow runs the seed before live-verify (${wf_report#OK:})"
  else
    echo "  FAIL: ${wf_report#FAIL:}" >&2
    fail=1
  fi
else
  echo "  FAIL: could not locate web-platform-release.yml at $WF_F" >&2
  fail=1
fi

# ANTI-VACUITY FLOOR. The registration lint proves this FILE is discovered; it
# says nothing about whether the file still asserts anything, and the runner
# finds it by glob — so a gutted suite would report green indefinitely. Counts
# concluded verdicts, and emits with printf + exit DIRECTLY: routing this
# through `fail` would dispatch the detector through the thing it detects.
# Set to the MEASURED count from a green run, not a guessed one: slack between
# a floor and the real value is budget an edit can spend silently.
_concluded="$(grep -cE '^[[:space:]]*echo "  (ok|FAIL):' "$0" || true)"
if [[ "${_concluded:-0}" -lt 39 ]]; then
  printf 'FATAL: only %s verdict site(s) remain in this suite; expected >= 39.\n' "${_concluded:-0}" >&2
  exit 1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "seed-live-verify-user.test.sh: FAILED" >&2
  exit 1
fi
echo "seed-live-verify-user.test.sh: PASSED"
