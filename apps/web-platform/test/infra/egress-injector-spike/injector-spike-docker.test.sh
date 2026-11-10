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
#   CHECK_WIDEN DEADLINE XTRACE_FORBIDDEN
#
# Slice status (2026-11-10). Built: preflight, the harness self-test, the local stack, the R21 guard, the inline
# CHECK widening (CTO R5, D4). Not built yet, each recorded `unmeasurable` with reason `arm-not-implemented:<what>`:
# the network, gateway, stubs, hook, router and injector bring-up and every criterion arm. A run of this slice is
# therefore INCONCLUSIVE by construction; it proves the CI plumbing, never a mechanism. The arms are task 1.8 in
# knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/tasks.md.
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
# Outside SPIKE_WORK: the EXIT trap removes the work directory, and the results must outlive it.
SPIKE_OUT="${INJECTOR_SPIKE_OUT:-${TMPDIR:-/tmp}/injector-spike-results.$$.json}"
export SPIKE_DIR SPIKE_WORK SPIKE_RECORDS SPIKE_OUT
# shellcheck source=lib/harness.sh
source "$SPIKE_DIR/lib/harness.sh"

cleanup() {
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
[[ -n "$API_URL" && -n "$SERVICE_KEY" ]] || harness_fail SUPABASE_STATUS "status output carries no API_URL or SERVICE_ROLE_KEY"
mask "$SERVICE_KEY"
( umask 077 && printf '%s\n' "$SERVICE_KEY" > "$SPIKE_WORK/service-role.key" )
unset SERVICE_KEY

# R21: the same guard the hook runs, before the suite itself writes to the database.
node --input-type=module -e '
import { readFileSync } from "node:fs";
const hook = await import(process.argv[1]);
const status = hook.parseStatusEnv(readFileSync(process.argv[3], "utf8"));
const r = hook.checkSupabaseTarget({ url: process.argv[2], key: readFileSync(process.argv[4], "utf8").trim(), status });
if (!r.ok) { console.log(`guard refused: ${r.reason}`); process.exit(1); }
' "$SPIKE_DIR/approval-hook.mjs" "$API_URL" "$SPIKE_WORK/supabase-status.env" "$SPIKE_WORK/service-role.key" \
  > "$SPIKE_WORK/guard.log" 2>&1 || harness_fail SUPABASE_GUARD "$(head -1 "$SPIKE_WORK/guard.log")"

# CTO R5 / D4: widen the closed tool_name CHECK for the one spike tool name, inside the database container, looking
# the constraint up in pg_constraint rather than assuming its name. The new expression is the old one OR the spike
# name, so every existing name keeps its meaning. Recorded as input for the migration #11637 owns.
DB_CTR="$(docker ps --filter 'name=supabase_db' --format '{{.Names}}' | head -1)"
[[ -n "$DB_CTR" ]] || harness_fail CHECK_WIDEN "no supabase_db container"
TOOL_NAME="$(node --input-type=module -e 'const h = await import(process.argv[1]); console.log(h.SPIKE_TOOL_NAME)' "$SPIKE_DIR/approval-hook.mjs")"
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

# --- Arms not built yet (task 1.8) -----------------------------------------------------------------------------------
# Recorded honestly so the floor reads INCONCLUSIVE rather than a skip or a pass.
record_verdict 1 unmeasurable "arm-not-implemented:sandbox-scan-and-cli-tier-probes"
record_verdict 2 unmeasurable "arm-not-implemented:sdk-sandbox-clients-arms-a-and-b"
record_verdict 3 unmeasurable "arm-not-implemented:approval-lifecycle"
record_verdict 4 unmeasurable "arm-not-implemented:allowlisted-reads"
record_verdict 5 unmeasurable "arm-not-implemented:cross-session"
record_verdict 6 unmeasurable "arm-not-implemented:adr-278-controls-and-log-grep"
record_verdict 7 unmeasurable "arm-not-implemented:add-verb-overlay"
record_verdict 8 unmeasurable "arm-not-implemented:failure-modes"
record_verdict 9 unmeasurable "arm-not-implemented:ca-scope"
finalize
