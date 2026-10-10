#!/usr/bin/env bash
#
# (#9175) Drift-guards for the inngest-provision forced-race rehearsal route.
#
# WHAT THIS PROTECTS. The rehearsal boots the REAL cloud-init-inngest.yml on a throwaway
# host so the #8539 NIC race is rehearsed on demand rather than next-discovered in
# production. Its safety rests on a small number of properties that are individually cheap
# to break and collectively catastrophic to lose:
#
#   1. The rehearsal root references NO production address (no prod resource address, no
#      remote state; data.hcloud_network.private is the one permitted READ). `-target` is
#      TRANSITIVE ON DEPENDENCIES, so a single reference could drag hcloud_server.inngest
#      into a rehearsal apply's plan closure.
#   2. Every hcloud_*/doppler_* address in the root carries `.rehearsal` — a mechanical
#      contract, not a naming convention.
#   3. The scratch Doppler shape is a NON-INHERITING environment (doppler_environment), not
#      a branch config under prd — a branch resolves the root's secrets and a rehearsal
#      token would read all of prod soleur-inngest.
#   4. nic_attached has NO default (a run that forgot it must fail at plan time), and it
#      gates exactly one resource (hcloud_server_network.rehearsal) — the Phase-B delta the
#      plan-shape guard asserts.
#   5. The pinned checksums the render feeds the template are COPIES of the parent root's —
#      a pin bump that misses this root makes the rehearsal verify a different binary
#      (#6570's divergence class). They are pinned EQUAL here.
#   6. The workflow cannot commit its own evidence (contents: read + artifact upload only),
#      is dispatch-only, dry_run defaults true, joins the parent's widest apply
#      concurrency group, and runs under the reviewer-gated environment.
#   7. The parent apply workflow's push path excludes this root's files — a rehearsal-only
#      edit must never trigger a production apply.
#   8. The prefix's TRAILING HYPHEN — `soleur-inngest` is a prefix of
#      `soleur-inngest-rehearsal-…`; a sweep pattern missing it would match the PRODUCTION
#      host.
#
# EVERY ASSERTION OVER HCL OR YAML STRIPS COMMENTS FIRST — this route's rationale
# legitimately NAMES the production addresses it must not reference
# (cq-assert-anchor-not-bare-token).
#
# Presence under apps/web-platform/infra/ IS registration — derived and run by
# run-registered-suites.sh (#8736).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../../.." && pwd)"
REH="${DIR}/inngest-provision-rehearsal"
WF="${ROOT}/.github/workflows/inngest-provision-rehearsal.yml"
APPLY_WF="${ROOT}/.github/workflows/apply-web-platform-infra.yml"
DRIFT_WF="${ROOT}/.github/workflows/scheduled-terraform-drift.yml"
CAPTURE="${ROOT}/scripts/followthroughs/inngest-provision-rehearsal-capture.sh"
SHAPE="${ROOT}/scripts/inngest-provision-plan-shape.sh"
PROBE="${ROOT}/scripts/inngest-provision-rehearsal-probe.sh"

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '       %s\n' "$2" >&2; }
yes() { cases=$((cases + 1)); if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
no()  { cases=$((cases + 1)); if eval "$2" >/dev/null 2>&1; then fail "$1"; else pass "$1"; fi; }

for f in "$REH/main.tf" "$REH/variables.tf" "$REH/rehearsal.tf" "$REH/.terraform.lock.hcl" "$WF" "$CAPTURE" "$SHAPE"; do
  yes "exists: ${f##*/}" "[[ -f '$f' ]]"
done

# Comment-stripped code of the root — assertions below read THIS, never the raw files.
REH_CODE="$(mktemp)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -f "$REH_CODE"' EXIT
for f in "$REH"/*.tf; do sed 's/^[[:space:]]*#.*$//' "$f"; done > "$REH_CODE"

# ── 0. The root's file inventory is closed ─────────────────────────────────────
# Terraform also loads *.tf.json, *.tfvars{,.json} (auto tfvars BEAT TF_VAR_* env), and any
# subdirectory reachable via module blocks. A file-shape escape carries real config outside
# every grep window this suite (and the workflow census) applies. The inventory is pinned.
_extra_files="$(ls -A "$REH" | grep -vE '^(main\.tf|variables\.tf|rehearsal\.tf|\.terraform\.lock\.hcl|\.terraform)$' || true)"
yes "the root contains EXACTLY {main,variables,rehearsal}.tf + the lockfile (no .tf.json/.tfvars/subdirs)" \
  "[[ -z '$_extra_files' ]]"

# ── 1. No production references (the separation is the safety argument) ─────────
yes "no production resource address is referenced (hcloud_*.inngest / doppler_*.inngest / remote state)" \
  "! grep -qE 'hcloud_(server|volume|firewall|network|ssh_key)\.inngest\b|doppler_(environment|project|config|service_token|secret)\.inngest|terraform_remote_state|data\.hcloud_server\.' '$REH_CODE'"
no "hcloud_network.private is referenced ONLY as a data source" \
  "grep -vqF 'data.hcloud_network.private' < <(grep -E '(^|[^.a-z_])hcloud_network\.private\b' '$REH_CODE')"
yes "a distinct state key carries the rehearsal root (comment-stripped — a comment literal cannot satisfy this)" \
  "grep -qF 'web-platform/inngest-provision-rehearsal/terraform.tfstate' '$REH_CODE'"
yes "the backend has no lockfile (R2 lacks conditional writes — the workflow's concurrency group is the serializer)" \
  "grep -qF 'use_lockfile = false' '$REH_CODE'"
no "the root carries no import or moved block (a rename-shaped adoption is how a prod address could ride in)" \
  "grep -qE '^(import|moved)[[:space:]]*\{|^[[:space:]]*(import|moved)[[:space:]]*\{' '$REH_CODE'"
yes "the scratch host's sdk_url is loopback (it can never adopt a prod registry or reach prod web)" \
  "grep -qE 'sdk_url[[:space:]]*=[[:space:]]*\"http://127\.0\.0\.1:3000/api/inngest\"' '$REH_CODE'"
yes "web_host_private_ips is loopback (the isolation self-check sees exactly one IP)" \
  "grep -qE 'web_host_private_ips[[:space:]]*=[[:space:]]*\"127\.0\.0\.1\"' '$REH_CODE'"
yes "the rehearsal private IP is 10.0.1.60 and feeds inngest_private_ip (collides with no prod allocation)" \
  "grep -qE 'rehearsal_private_ip[[:space:]]*=[[:space:]]*\"10\.0\.1\.60\"' '$REH_CODE' && grep -qE 'inngest_private_ip[[:space:]]*=[[:space:]]*local\.rehearsal_private_ip' '$REH_CODE'"

# ── 2. The .rehearsal addressing contract ─────────────────────────────────────
BAD_ADDR="$(grep -oE 'resource "(hcloud|doppler|random|tls)_[a-z_]+" "[a-z_]+"' "$REH_CODE" \
            | grep -vE '"rehearsal(_[a-z0-9_]+)?"' || true)"
yes "every managed resource address carries .rehearsal" "[[ -z '$BAD_ADDR' ]]"
yes "the ONLY data source is the private-network read, bound to soleur-private by name" \
  "[[ \$(grep -oE 'data \"[a-z_]+\" \"[a-z_]+\"' '$REH_CODE' | grep -vc 'hcloud_network.*private') -eq 0 ]] && grep -qE 'name[[:space:]]*=[[:space:]]*\"soleur-private\"' < <(awk '/data \"hcloud_network\" \"private\"/{f=1} f&&/^}/{exit} f' '$REH_CODE' )"

# ── 3. Non-inheriting scratch config ──────────────────────────────────────────
yes "the scratch config is a doppler_environment (non-inheriting root config)" \
  "grep -qF 'resource \"doppler_environment\" \"rehearsal\"' '$REH_CODE'"
no "no doppler_config branch exists (a branch under prd inherits prod secrets)" \
  "grep -qF 'resource \"doppler_config\"' '$REH_CODE'"
yes "the environment lives on the soleur-inngest project" \
  "grep -qF 'project = \"soleur-inngest\"' < <(grep -A4 'resource \"doppler_environment\" \"rehearsal\"' '$REH_CODE' )"
yes "the service token is READ-scoped (the provision path only reads)" \
  "grep -qE 'access[[:space:]]*=[[:space:]]*\"read\"' < <(awk '/resource \"doppler_service_token\" \"rehearsal\"/{f=1} f&&/^}/{print;exit} f' '$REH_CODE' )"
yes "INNGEST_REDIS_LUKS_KEY is seeded in the scratch env (the LUKS stage FATALs on an empty key — 'refusing an unencrypted mount', attempt-3)" \
  "grep -qF 'name       = \"INNGEST_REDIS_LUKS_KEY\"' '$REH_CODE'"
yes "INNGEST_DIAGNOSTIC_BOOT is staged true (the rehearsal can never run a live scheduler)" \
  "grep -qE 'value[[:space:]]*=[[:space:]]*\"true\"' < <(awk '/resource \"doppler_secret\" \"rehearsal_diagnostic_boot\"/{f=1} f&&/^}/{print;exit} f' '$REH_CODE' )"

# ── 4. The forced-race toggle ─────────────────────────────────────────────────
yes "nic_attached is a required variable (no default)" \
  "! grep -q 'default' < <(awk '/variable \"nic_attached\"/{f=1} f&&/^}/{print;exit} f' '$REH_CODE' )"
yes "rehearsal_run_id is digit-validated (it lands in names/slugs)" \
  "grep -qF '[0-9]' < <(grep -A8 'variable \"rehearsal_run_id\"' '$REH_CODE' )"
yes "the NIC attachment is count-gated on nic_attached — inside the hcloud_server_network block itself" \
  "grep -qE 'count[[:space:]]*=[[:space:]]*var\.nic_attached \? 1 : 0' < <(awk '/resource \"hcloud_server_network\" \"rehearsal\"/{f=1} f&&/^}/{exit} f' '$REH_CODE' )"
yes "the rehearsal host block carries NO inline network{} (Phase A is NIC-absent by definition)" \
  "! grep -qE '\\bnetwork[[:space:]]*\\{' < <(awk '/resource \"hcloud_server\" \"rehearsal\"/{f=1} f&&/^}/{exit} f' '$REH_CODE' )"

yes "Sentry is suppressed on the rehearsal (empty DSN — stage-filtered prod alerts must not page)" \
  "grep -qE 'sentry_dsn[[:space:]]*=[[:space:]]*\"\"' '$REH_CODE'"
yes "the zot endpoint literal equals the parent's registry_private_ip operand" \
  "grep -qE 'zot_registry_endpoint[[:space:]]*=[[:space:]]*\"10\.0\.1\.30:5000\"' '$REH_CODE' && grep -qF 'registry_private_ip = \"10.0.1.30\"' '$DIR/zot-registry.tf'"

# ── 5. Render parity: checksums copied from the parent must equal it ──────────
for pair in \
  'inngest_cli_sha256:52c07d837088a6712acd15b8edd4191f961b69884541f468a3c1b9bb4348a4e5' \
  'inngest_cli_sha256_arm64:58db59dbe39afd7472c7c59bd7cc9f82f5da5810dabdac40b2bde3a8338aa7b5' \
  'vector_sha256:8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1' \
  'vector_sha256_arm64:365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6' \
  ; do
  key="${pair%%:*}"; sha="${pair##*:}"
  parent_file="$DIR/inngest.tf"; [[ "$key" == vector* ]] && parent_file="$DIR/vector.tf"
  cases=$((cases + 1))
  if grep -qF "$sha" "$parent_file" && grep -qF "$sha" "$REH/rehearsal.tf"; then
    pass "${key} matches the parent root's pinned checksum"
  else
    fail "${key} DIVERGED from the parent root (${parent_file##*/}) — a pin bump missed this root (#6570 class)"
  fi
done
# doppler_sha256 is a per-arch ternary in both files — pin the two operand literals.
for sha in f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143 9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db; do
  cases=$((cases + 1))
  if grep -qF "$sha" "$DIR/inngest-host.tf" && grep -qF "$sha" "$REH/rehearsal.tf"; then
    pass "doppler_sha256 operand ${sha:0:12}… matches inngest-host.tf"
  else
    fail "doppler_sha256 operand ${sha:0:12}… DIVERGED from inngest-host.tf"
  fi
done
yes "the render applies the same strip+gzip as prod (byte-fidelity is the evidence)" \
  "grep -qF 'base64gzip' '$REH_CODE' && grep -qF 'inngest_rationale_strip' '$REH_CODE'"
yes "inngest_doppler_config threads the scratch config into the render" \
  "grep -qF 'inngest_doppler_config = local.rehearsal_doppler_config' '$REH_CODE'"
no "the rehearsal render never passes a literal prod config" \
  "grep -qE 'inngest_doppler_config[[:space:]]*=[[:space:]]*\"prd\"' '$REH_CODE'"

# ── 6. The workflow contract ──────────────────────────────────────────────────
yes "the workflow is dispatch-only (no push/pull/schedule trigger)" \
  "! grep -qE '^\s*(push|pull_request|pull_request_target|schedule|merge_group):' < <(awk '/^on:/{f=1;next} /^[a-z]/ {f=0} f' '$WF' )"
yes "dry_run defaults true (a bare 'check the plan' must not spend a host)" \
  "grep -qF 'default: true' < <(grep -A6 'dry_run:' '$WF' )"
yes "a teardown_only recovery arm exists" \
  "grep -qF 'teardown_only' '$WF'"
yes "the reviewer-gated environment is bound" \
  "grep -qF 'environment: web-platform-infra-apply' '$WF'"
yes "the workflow joins the parent's widest apply concurrency group" \
  "grep -qF 'group: terraform-apply-web-platform-host' '$WF'"
yes "every ZOT_PULL_TOKEN read pairs soleur/prd with the DOPPLER_TOKEN_PRD override (the default token is prd_terraform-scoped)" \
  "[[ \$(grep -c 'DOPPLER_TOKEN=.\$DOPPLER_TOKEN_PRD. doppler secrets get ZOT_PULL_TOKEN -p soleur -c prd' '$WF') -ge 4 ]] && [[ \$(grep 'secrets get ZOT_PULL_TOKEN' '$WF' | grep -vc 'DOPPLER_TOKEN_PRD') -eq 0 ]]"
no "no ZOT_PULL_TOKEN read targets the wrong project (soleur-registry is the mirror, not the root)" \
  "grep -qF 'get ZOT_PULL_TOKEN -p soleur-registry' '$WF'"
yes "contents: read (the workflow cannot commit its own evidence)" \
  "grep -qE '^\s+contents: read' '$WF'"
yes "the confirm token is REHEARSE-INNGEST-PROVISION" \
  "grep -qF 'REHEARSE-INNGEST-PROVISION' '$WF'"
yes "the rehearsal-directory env var names this root" \
  "grep -qF 'REHEARSAL_DIR: apps/web-platform/infra/inngest-provision-rehearsal' '$WF'"
yes "terraform init runs -lockfile=readonly (the committed lockfile IS the pin)" \
  "grep -qE '^[2-9]' < <(grep -cF 'lockfile=readonly' '$WF')"  # init runs in BOTH jobs
yes "terraform runs pinned at the repo's TERRAFORM_VERSION" \
  "grep -qF 'TERRAFORM_VERSION: \"1.10.5\"' '$WF'"
yes "the plan-shape guard runs in BOTH modes (additive AND nic-attach)" \
  "grep -qF 'plan-a.json additive' '$WF' && grep -qF 'plan-b.json nic-attach' '$WF'"
yes "the evidence capture runs in all three modes (phase-a, phase-b, post-reboot)" \
  "grep -qF -- '--mode phase-a' '$WF' && grep -qF -- '--mode phase-b' '$WF' && grep -qF -- '--mode post-reboot' '$WF'"
yes "the reboot is the Hetzner API (never SSH)" \
  "grep -qF 'actions/reboot' '$WF' && ! grep -qE 'ssh |ssh-key' '$WF'"
yes "the phase ordering is apply_A -> capture_A -> plan_B -> apply_B -> settle -> reboot -> capture_C" \
  "awk '/id: apply_a/{a=NR} /id: cap_a/{b=NR} /id: plan_b/{c=NR} /id: apply_b/{d=NR} /id: settle/{s=NR} /id: reboot/{e=NR} /id: cap_c/{f=NR} END{exit !(a<b && b<c && c<d && d<s && s<e && e<f)}' '$WF'"
yes "teardown is its own job gated always() (a ceiling in rehearse cannot starve it)" \
  "grep -qF 'always()' < <(awk '/^  teardown:/{f=1} f&&/if:/{print;exit}' '$WF' )"
yes "teardown runs under the infra-privileged environment (state writes need the credential tier)" \
  "grep -qF 'infra-privileged' < <(awk '/^  teardown:/{f=1} f&&/environment:/{print;exit}' '$WF' )"
yes "teardown destroys with nic_attached=false (the prod-network data read stays out of the destroy graph)" \
  "grep -qF 'var nic_attached=false' '$WF'"
yes "the evidence artifact name carries run_attempt (immutable names collide on re-run)" \
  "grep -qF '\${{ github.run_id }}-\${{ github.run_attempt }}' '$WF'"
yes "every step carries a timeout-minutes bound" \
  "python3 -c 'import yaml,sys; d=yaml.safe_load(open(\"$WF\")); sys.exit(0 if all(\"timeout-minutes\" in s for j in d[\"jobs\"].values() for s in j[\"steps\"]) else 1)'"
yes "the job ceiling covers the step sum" \
  "python3 -c 'import yaml,sys; d=yaml.safe_load(open(\"$WF\")); cap=d[\"jobs\"][\"rehearse\"][\"timeout-minutes\"]; tot=sum(s[\"timeout-minutes\"] for s in d[\"jobs\"][\"rehearse\"][\"steps\"]); sys.exit(0 if cap>=tot else 1)'"
yes "the evidence is uploaded as an ARTIFACT (never committed)" \
  "grep -qF 'actions/upload-artifact' '$WF' && ! grep -qE 'git (add|commit|push)' '$WF'"
yes "the in-workflow orphan assertion lists all four hcloud kinds" \
  "grep -qF 'servers volumes ssh_keys firewalls' '$WF'"
yes "since-file writers emit the capture's contract (YYYY-MM-DDTHH:MM:SS — no zone suffix; a trailing Z is a rc=64 refusal)" \
  "[[ \$(grep -c 'date -u +%Y-%m-%dT%H:%M:%S > .*-since.txt' '$WF') -ge 3 ]] && ! grep -q 'date -u +%Y-%m-%dT%H:%M:%SZ' '$WF'"
yes "every parseDateTime64BestEffort call carries the precision arg (the 2-arg (s,'UTC') form is Code 43 — proven live)" \
  "! grep -qE \"parseDateTime64BestEffort\\([^,]+, 'UTC'\\)\" < <(grep -oE 'parseDateTime64BestEffort\\([^)]*\\)' '$ROOT/scripts/followthroughs/inngest-provision-rehearsal-capture.sh') && [[ \$(grep -cE 'parseDateTime64BestEffort.*, 3, .UTC.' '$ROOT/scripts/followthroughs/inngest-provision-rehearsal-capture.sh') -ge 2 ]]"
no "no comment line sits inside a doppler run -- backslash-continuation (a # there is an argv word — proven by the first teardown run)" \
  "awk '/doppler run.*--[[:space:]]*\\\\$/{n=NR} n && NR>n && /^[[:space:]]*#/{print; found=1} n && NR>n && !/^[[:space:]]*#/{n=0} END{exit found?0:1}' '$WF'"

# ── 7. The push-path exclusion ────────────────────────────────────────────────
yes "apply-web-platform-infra.yml excludes this root from its push trigger" \
  "grep -qF '\"!apps/web-platform/infra/inngest-provision-rehearsal/**\"' '$APPLY_WF'"
yes "the exclusion sits AFTER the glob it narrows (later patterns win)" \
  "awk '/paths:/{f=1} f&&/apps\/web-platform\/infra\/\*\*/{a=NR} f&&/inngest-provision-rehearsal/{b=NR} f&&/workflow_dispatch:/{exit} END{exit !(a && b && b>a)}' '$APPLY_WF'"

# ── 8. Prefix + sweep wiring ──────────────────────────────────────────────────
_pfx_tf="$(grep -oE 'rehearsal_host_name[[:space:]]*=[[:space:]]*"[^"]*"' "$REH_CODE" | sed -n '1p' | sed 's/.*"\(.*\)"$/\1/')"
_pfx_wf="$(grep -oE '^[[:space:]]*REHEARSAL_PREFIX:[[:space:]]*\S+' "$WF" | sed -n '1p' | awk '{print $2}')"
_pfx_drift="$(grep -oE '^[[:space:]]*REHEARSAL_PREFIX:[[:space:]]*\S+' "$DRIFT_WF" | sed -n '1p' | awk '{print $2}')"
cases=$((cases + 1))
if [[ "$_pfx_wf" == "soleur-inngest-rehearsal-" ]]; then
  pass "the dispatch workflow pins the trailing-hyphen rehearsal prefix"
else
  fail "workflow REHEARSAL_PREFIX is '${_pfx_wf}' — expected soleur-inngest-rehearsal- (the trailing hyphen is load-bearing: soleur-inngest is a PREFIX of it)"
fi
cases=$((cases + 1))
if [[ "$_pfx_tf" == "${_pfx_wf}"* ]]; then
  pass "the Terraform host name starts with the prefix the sweep matches (${_pfx_wf})"
else
  fail "the Terraform host name '${_pfx_tf}' does not start with the sweep prefix '${_pfx_wf}' — the sweep would match zero servers while a paying host runs"
fi
yes "the drift sweep knows this prefix" \
  "grep -qF 'soleur-inngest-rehearsal-' '$DRIFT_WF'"
yes "the drift sweep knows the rehearsal label" \
  "grep -qF 'soleur-inngest-provision-rehearsal' '$DRIFT_WF'"
yes "the drift sweep enumerates rehearsal_* environments in soleur-inngest" \
  "grep -qF 'rehearsal_' '$DRIFT_WF' && grep -qF 'soleur-inngest' '$DRIFT_WF'"

# ── Cross-checks on the sibling artifacts ─────────────────────────────────────
yes "the capture script is executable and bash-syntax-clean" \
  "[[ -x '$CAPTURE' ]] && bash -n '$CAPTURE'"
yes "the capture script carries the terminal verdict sentinel" \
  "grep -qF 'INNGEST_PROVISION_CAPTURE_VERDICT' '$CAPTURE'"
yes "the capture script confines reads to rehearsal hosts" \
  "grep -qF 'soleur-inngest-rehearsal-' '$CAPTURE'"
# The write-on-PASS property, pinned by POSITION: exactly one `$OUT` append exists and it
# sits after the LAST `exit 1`/`exit 2`, so no FAIL/TRANSIENT path can reach it.
_w_count="$(grep -cF '>> "$OUT"' "$CAPTURE")"
_w_pos="$(grep -nF '>> "$OUT"' "$CAPTURE" | head -1 | cut -d: -f1)"
_e_pos="$(grep -nE 'exit [12]' "$CAPTURE" | tail -1 | cut -d: -f1)"
cases=$((cases + 1))
if [[ "$_w_count" == 1 && "$_w_pos" -gt "${_e_pos:-0}" ]]; then
  pass "the capture writes on PASS only (the single evidence append sits past the last early exit)"
else
  fail "the capture writes on PASS only" "appends=${_w_count} at :${_w_pos}; last exit at :${_e_pos}"
fi
yes "the plan-shape guard is executable and bash-syntax-clean" \
  "[[ -x '$SHAPE' ]] && bash -n '$SHAPE'"
yes "the probe script exists and is executable" \
  "[[ -f '$PROBE' ]] && [[ -x '$PROBE' ]] && bash -n '$PROBE'"

# ── floor (ADR-193) ───────────────────────────────────────────────────────────
MIN=40
if (( cases < MIN )); then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$cases" "$MIN" >&2
  exit 1
fi
printf '\n=== inngest-provision-rehearsal: %s passed, %s failed (%s assertions) ===\n' "$passes" "$fails" "$cases"
exit $(( fails > 0 ))
