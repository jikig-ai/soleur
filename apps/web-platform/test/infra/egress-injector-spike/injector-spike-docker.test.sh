#!/usr/bin/env bash
# Egress injector spike suite (#12517). Plan: knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md
#
# Measures criteria 1-9 on the production run tuple against the real approval RPCs on a throwaway local Supabase
# stack (CTO F-a), the real egress-forwarder.mjs and squid conf (unchanged), digest-pinned iron-proxy (F-b), hermetic
# stub destinations (F-f), and writes the raw results JSON (INJECTOR_SPIKE_OUT) whose verdict verdict.mjs computes.
#
# NEVER SELF-SKIPS. A missing tool or daemon is `FAIL <TOKEN>` and every criterion without a verdict is recorded
# `unmeasurable` with that token, so the verdict is INCONCLUSIVE and the exit is 1 (Guard 3). Tokens:
#   TOOL_UNAVAILABLE DOCKER_UNAVAILABLE SELFTEST SUPABASE_START SUPABASE_STATUS SUPABASE_GUARD MIGRATIONS
#   CHECK_WIDEN DEADLINE XTRACE_FORBIDDEN TUPLE_CHECK APPARMOR_UNAVAILABLE SYSCTL_UNAVAILABLE IMAGE_BUILD_FAILED
#   IMAGE_DRIFT IRON_PROXY NETWORK OWNERSHIP STUB_START SQUID_START CONTAINER_START_FAILED SESSION_PREP HOOK_START
#   SESSION_UP SEED DRIVER
#
# Slice status (2026-11-10). Built: preflight, the harness self-test, the local stack, the R21 guard, the inline
# CHECK widening (CTO R5, D4), and the topology (lib/bringup.sh: image, prod posture, networks, real squid, stub,
# app container, hook, three sessions) with synthetic seeding (lib/arms.sh). Criterion arms not built yet are each
# recorded `unmeasurable` with reason `arm-not-implemented:<what>`, so such a run reads INCONCLUSIVE by construction.
# The arms are task 1.8 in knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/tasks.md.
#
# Secrets: every value is a synthesized decoy generated per run, masked in the CI log, kept out of env and argv of
# the processes under test, and never printed. xtrace is refused (a trace would print them).
# shellcheck disable=SC2016 # single-quoted sed and node programs are intentional; nothing in them should expand
set -uo pipefail
case "$-" in *x*) echo "FAIL XTRACE_FORBIDDEN: the suite refuses to run with xtrace on (it would print secrets)"; exit 1 ;; esac
unset GIT_TRACE GIT_CURL_VERBOSE GIT_TRACE_CURL GIT_TRACE_PACKET

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WP="$(cd "$SPIKE_DIR/../../.." && pwd)"
REPO="$(cd "$WP/../.." && pwd)"
SPIKE_WORK="$(mktemp -d -t soleur-run.$$.XXXXXXXX)" || { echo "FAIL TOOL_UNAVAILABLE: mktemp"; exit 1; }
SPIKE_RECORDS="$SPIKE_WORK/records.jsonl"
SPIKE_OBSERVATIONS="$SPIKE_WORK/observations.jsonl"
# Outside SPIKE_WORK: the EXIT trap removes the work directory, and the results must outlive it.
SPIKE_OUT="${INJECTOR_SPIKE_OUT:-${TMPDIR:-/tmp}/injector-spike-results.$$.json}"
export SPIKE_DIR SPIKE_WORK SPIKE_RECORDS SPIKE_OUT SPIKE_OBSERVATIONS
# shellcheck source=lib/harness.sh
source "$SPIKE_DIR/lib/harness.sh"
# shellcheck source=lib/bringup.sh
source "$SPIKE_DIR/lib/bringup.sh"
# shellcheck source=lib/arms.sh
source "$SPIKE_DIR/lib/arms.sh"

cleanup() {
  spike_teardown
  case "$SPIKE_WORK" in /*/soleur-run.*) rm -rf -- "$SPIKE_WORK" ;; esac
}
trap cleanup EXIT

# Internal deadline: the job has 30 minutes; at 25 the suite records what it has and finalizes INCONCLUSIVE.
SPIKE_DEADLINE=$(( $(date +%s) + ${INJECTOR_SPIKE_DEADLINE_S:-1500} ))
check_deadline() { (( $(date +%s) < SPIKE_DEADLINE )) || harness_fail DEADLINE "internal 25-minute deadline reached during: $1"; }

export SPIKE_COMMIT SPIKE_DATE SPIKE_MACHINE SPIKE_SDK_PIN SPIKE_IRON_PROXY_DIGEST
SPIKE_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
SPIKE_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SPIKE_MACHINE="$(uname -srm) cpus=$(nproc 2>/dev/null || echo ?)"
SPIKE_SDK_PIN="$(node -p 'require(process.argv[1]).devDependencies?.["@anthropic-ai/claude-agent-sdk"] ?? require(process.argv[1]).dependencies?.["@anthropic-ai/claude-agent-sdk"] ?? "unknown"' "$WP/package.json" 2>/dev/null || echo unknown)"
SPIKE_IRON_PROXY_DIGEST="$(sed -n 's/.*`docker\.io\/ironsh\/iron-proxy@\(sha256:[0-9a-f]\{64\}\)`.*/\1/p' "$SPIKE_DIR/iron-proxy-image.provenance.md" | head -1)"

# --- Preflight ------------------------------------------------------------------------------------------------------
for tool in docker node python3 openssl git curl psql supabase; do
  command -v "$tool" >/dev/null 2>&1 || harness_fail TOOL_UNAVAILABLE "$tool not on PATH"
done
docker info >/dev/null 2>&1 || harness_fail DOCKER_UNAVAILABLE "docker info failed"
[[ -n "$SPIKE_IRON_PROXY_DIGEST" ]] || harness_fail TOOL_UNAVAILABLE "iron-proxy digest not readable from the provenance file"
harness_selftest || harness_fail SELFTEST "instrument self-test failed"

# --- Local Supabase stack (CTO F-a, R5, R21) -------------------------------------------------------------------------
SUPA="$WP/scripts/supabase-local.sh"
DB_URL="postgres://postgres:postgres@127.0.0.1:54322/postgres"
( cd "$WP" && bash "$REPO/.github/scripts/ghcr-pull-with-retry.sh" "$SUPA" start ) > "$SPIKE_WORK/supabase-start.log" 2>&1 \
  || harness_fail SUPABASE_START "supabase-local.sh start failed (log: $(tail -3 "$SPIKE_WORK/supabase-start.log" | tr '\n' ' '))"
( cd "$WP" && "$SUPA" assert --require-stack ) > "$SPIKE_WORK/supabase-assert.log" 2>&1 \
  || harness_fail SUPABASE_START "stack is not loopback-only bound"
( cd "$WP" && "$SUPA" db reset ) > "$SPIKE_WORK/supabase-reset.log" 2>&1 \
  || harness_fail SUPABASE_START "db reset failed"
check_deadline "supabase start"

psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE IF NOT EXISTS public._schema_migrations (filename TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now(), content_sha TEXT);" \
  > "$SPIKE_WORK/bootstrap.log" 2>&1 || harness_fail MIGRATIONS "migration-tracking bootstrap failed"
( cd "$WP" && DATABASE_URL="$DB_URL" ALLOW_UNMERGED_DEV_APPLY=1 bash scripts/run-migrations.sh --bootstrap=skip ) \
  > "$SPIKE_WORK/migrations.log" 2>&1 || harness_fail MIGRATIONS "run-migrations.sh failed (log: $(tail -3 "$SPIKE_WORK/migrations.log" | tr '\n' ' '))"
check_deadline "migrations"

( cd "$WP" && "$SUPA" status -o env ) > "$SPIKE_WORK/supabase-status.env" 2>/dev/null \
  || harness_fail SUPABASE_STATUS "supabase status -o env failed"
API_URL="$(sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$SPIKE_WORK/supabase-status.env" | head -1)"
SERVICE_KEY="$(sed -n 's/^SERVICE_ROLE_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$SPIKE_WORK/supabase-status.env" | head -1)"
ANON_KEY="$(sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$SPIKE_WORK/supabase-status.env" | head -1)"
[[ -n "$API_URL" && -n "$SERVICE_KEY" && -n "$ANON_KEY" ]] || harness_fail SUPABASE_STATUS "status output carries no API_URL, SERVICE_ROLE_KEY or ANON_KEY"
mask "$SERVICE_KEY"; mask "$ANON_KEY"
( umask 077 && printf '%s\n' "$SERVICE_KEY" > "$SPIKE_WORK/service-role.key" && printf '%s\n' "$ANON_KEY" > "$SPIKE_WORK/anon.key" )
unset SERVICE_KEY ANON_KEY

# R21: the same guard the hook runs, before the suite itself writes to the database.
# The module path travels in SPIKE_HOOK_MODULE, never argv: under `node -e`, argv[1] is the first extra argument, and
# each spike module runs its program when argv[1] names it, so passing the hook path there ran the hook's main()
# (which then read the next argument as its config file; CI run 42795274079).
SPIKE_HOOK_MODULE="$SPIKE_DIR/approval-hook.mjs"
export SPIKE_HOOK_MODULE
hook_eval() { node --input-type=module -e "const hook = await import(process.env.SPIKE_HOOK_MODULE); $1" "${@:2}"; }
hook_eval '
const { readFileSync } = await import("node:fs");
const status = hook.parseStatusEnv(readFileSync(process.argv[2], "utf8"));
const r = hook.checkSupabaseTarget({ url: process.argv[1], key: readFileSync(process.argv[3], "utf8").trim(), status });
if (!r.ok) { console.log(`guard refused: ${r.reason}`); process.exit(1); }
console.log("guard ok");' "$API_URL" "$SPIKE_WORK/supabase-status.env" "$SPIKE_WORK/service-role.key" \
  > "$SPIKE_WORK/guard.log" 2>&1 || harness_fail SUPABASE_GUARD "$(head -1 "$SPIKE_WORK/guard.log")"
grep -qx 'guard ok' "$SPIKE_WORK/guard.log" || harness_fail SUPABASE_GUARD "guard printed no verdict: $(head -1 "$SPIKE_WORK/guard.log")"

# CTO R5 / D4: widen the closed tool_name CHECK for the one spike tool name, inside the database container, looking
# the constraint up in pg_constraint rather than assuming its name. The new expression is the old one OR the spike
# name, so every existing name keeps its meaning. Recorded as input for the migration #11637 owns.
DB_CTR="$(docker ps --filter 'name=supabase_db' --format '{{.Names}}' | head -1)"
[[ -n "$DB_CTR" ]] || harness_fail CHECK_WIDEN "no supabase_db container"
TOOL_NAME="$(hook_eval 'console.log(hook.SPIKE_TOOL_NAME)')"
[[ "$TOOL_NAME" =~ ^[a-z_]+$ ]] || harness_fail CHECK_WIDEN "unexpected spike tool name"
docker exec -i "$DB_CTR" psql --no-psqlrc -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -v tool="$TOOL_NAME" > "$SPIKE_WORK/check-widen.log" 2>&1 <<'SQL' || harness_fail CHECK_WIDEN "$(tail -2 "$SPIKE_WORK/check-widen.log" | tr '\n' ' ')"
SELECT conname AS con, regexp_replace(pg_get_constraintdef(oid), '^CHECK ', '') AS expr
  FROM pg_constraint
 WHERE conrelid = 'public.approval_request'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%tool_name%'
\gset
\if :{?con}
\else
  \echo 'no tool_name CHECK found'
  \quit 3
\endif
SELECT format('ALTER TABLE public.approval_request DROP CONSTRAINT %I, ADD CONSTRAINT %I CHECK (%s OR tool_name = %L)',
              :'con', :'con', :'expr', :'tool') AS stmt
\gset
:stmt;
SELECT 'check-widened ' || :'con';
SQL
grep -q 'check-widened' "$SPIKE_WORK/check-widen.log" || harness_fail CHECK_WIDEN "widening did not report success"
echo "SOLEUR_SPIKE_STAGE stage=supabase-ready"
check_deadline "check widening"

# --- Topology (lib/bringup.sh) ---------------------------------------------------------------------------------------
spike_posture
spike_apparmor
spike_build_image
spike_iron_proxy_bin
check_deadline "image build"
spike_networks
spike_upstream_root
spike_hook_roots
spike_start_squid
spike_start_app

# --- Seeding: two synthetic owners (A, B), a conversation per hook session (CTO R16: fresh conversations) ----------
spike_seed_init
spike_seed_user ownerA WS_A
spike_seed_user ownerB WS_B
spike_new_conversation "$WS_A" CONV_A
spike_new_conversation "$WS_B" CONV_B
spike_new_conversation "$WS_A" CONV_C
spike_new_conversation "$WS_A" CONV_E
spike_sign_in ownerA
spike_sign_in ownerB

# Synthetic bare repositories (CLO: no real content). A's allowlist is spike/alpha, B's is spike/beta.
mkdir -p "$SPIKE_WORK/stub/repos/spike" || harness_fail STUB_START "mkdir repos"
for repo in alpha beta outside; do
  git init -q --bare -b main "$SPIKE_WORK/stub/repos/spike/$repo.git" \
    && git -C "$SPIKE_WORK/stub/repos/spike/$repo.git" config http.receivepack true \
    || harness_fail STUB_START "repo $repo"
  seedw="$SPIKE_WORK/seedrepo-$repo"
  git init -q -b main "$seedw" \
    && git -C "$seedw" -c user.email=spike@example.invalid -c user.name=spike commit -q --allow-empty -m "synthetic $repo" \
    && git -C "$seedw" push -q "$SPIKE_WORK/stub/repos/spike/$repo.git" main \
    || harness_fail STUB_START "seed $repo"
done

# Sessions: A (workspace A, flag on, spike/alpha), B (workspace B, flag on, spike/beta), C (workspace A, flag OFF),
# E (workspace A, flag on, rows created with a 60 s TTL: criterion 3's expiry arm).
spike_session_prepare sessA 0 "$WS_A" "$CONV_A"
spike_session_prepare sessB 1 "$WS_B" "$CONV_B"
spike_session_prepare sessC 2 "$WS_A" "$CONV_C"
spike_session_prepare sessE 3 "$WS_A" "$CONV_E"
python3 -I - "$SPIKE_WORK/stub/config.json" "$SPIKE_WORK/run" <<'PYSTUB' || harness_fail STUB_START "stub config"
import json, sys
decoys = [{"id": s, "value": open(f"{sys.argv[2]}/{s}/secrets/decoy.token").read()} for s in ("sessA", "sessB", "sessC", "sessE")]
json.dump({"listen": {"host": "0.0.0.0", "port": 443}, "certFile": "/stub/leaf.pem", "keyFile": "/stub/leaf.key",
           "repoRoot": "/stub/repos", "recordFile": "/stub/records.jsonl", "decoys": decoys}, open(sys.argv[1], "w"))
PYSTUB
spike_start_stub
spike_wait_log "$SPIKE_STUB_CTR" stub-github-listening 20 \
  || harness_fail STUB_START "stub did not listen: $(docker logs "$SPIKE_STUB_CTR" 2>&1 | tail -2 | tr '\n' ' ' | head -c 300)"

# The hook: the real local stack, the R21 guard inputs, a spike-only HMAC key, and the three sessions.
cp "$SPIKE_WORK/service-role.key" "$SPIKE_WORK/hookpriv/service-role.key" \
  && cp "$SPIKE_WORK/supabase-status.env" "$SPIKE_WORK/hookpriv/status.env" \
  || harness_fail HOOK_START "copy hook inputs"
( umask 077 && python3 -I -c 'import secrets; print(secrets.token_hex(32))' > "$SPIKE_WORK/hookpriv/hmac.key" ) \
  || harness_fail HOOK_START "hmac key"
python3 -I - "$SPIKE_WORK/hookpriv/hook.json" "$API_URL" "$WS_A:$CONV_A" "$WS_B:$CONV_B" "$WS_A:$CONV_C" "$WS_A:$CONV_E" <<'PYHOOK' || harness_fail HOOK_START "hook config"
import json, sys
out, url = sys.argv[1], sys.argv[2]
specs = [("sessA", sys.argv[3], ["spike/alpha"], True, None), ("sessB", sys.argv[4], ["spike/beta"], True, None),
         ("sessC", sys.argv[5], ["spike/alpha"], False, None), ("sessE", sys.argv[6], ["spike/alpha"], True, 60)]
sessions = []
for sid, wc, repos, flag, ttl in specs:
    ws, conv = wc.split(":")
    sessions.append({"sessionId": sid, "conversationId": conv, "workspaceId": ws, "requesterId": ws, "repositories": repos,
                     "flagOn": flag, "routerCredentialFile": f"/run/spike-hook/{sid}/router.pw",
                     "serverCertFile": f"/run/spike-hook/{sid}/server.pem", "serverKeyFile": f"/run/spike-hook/{sid}/server.key",
                     "socketPath": f"/run/spike/{sid}/hook/hook.sock", **({"ttlSeconds": ttl} if ttl else {})})
json.dump({"supabaseUrl": url, "serviceRoleKeyFile": "/run/spike-hook/service-role.key",
           "supabaseStatusFile": "/run/spike-hook/status.env", "hmacKeyFile": "/run/spike-hook/hmac.key",
           "policyFiles": ["/app/test/infra/egress-injector-spike/policy.yaml"],
           "clientRootCertFile": "/run/spike-hook/client-root.pem", "sessions": sessions}, open(out, "w"))
PYHOOK
spike_fix_owner "$SPIKE_WORK/run"
spike_fix_owner "$SPIKE_WORK/hookpriv"
spike_fix_owner "$SPIKE_WORK/stub"
spike_start_hook
spike_session_up sessA
spike_session_up sessB
spike_session_up sessC
spike_session_up sessE
echo "SOLEUR_SPIKE_STAGE stage=topology-ready"
check_deadline "topology"
# The expiry arm's 60 s wait overlaps the other arms (deepen pass, criterion 3).
arm_c3_expiry_start

# --- Arms (lib/arms.sh). Those not built yet are recorded honestly, so the floor reads INCONCLUSIVE, never a pass. --
record_verdict 1 unmeasurable "arm-not-implemented:sandbox-scan-and-cli-tier-probes"
arm_c2
arm_c3
arm_c4
arm_c5
record_verdict 6 unmeasurable "arm-not-implemented:adr-278-controls-and-log-grep"
record_verdict 7 unmeasurable "arm-not-implemented:add-verb-overlay"
record_verdict 8 unmeasurable "arm-not-implemented:failure-modes"
arm_c9
finalize
