#!/usr/bin/env bash
# Tests for scripts/lib/tweet-eligibility.sh — the brand-critical, fail-closed
# ship-tweet eligibility filter. Deterministic; no live `gh`. A mock `gh` on
# PATH returns canned PR metadata/paths driven by MOCK_* env vars.
#
# Eligibility contract (see #5021):
#   eligible  <= title starts with `feat(` (or `feat:`/`feat!`) AND label
#               `app:web-platform` present AND no deny label AND no deny path.
#   excluded  <= any deny label, any deny path, missing allow signal, gh error,
#               or empty metadata. Deny checks short-circuit regardless of the
#               allow-set. Fail-closed on every uncertainty.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/lib/tweet-eligibility.sh"
pass=0
fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label ${detail}" >&2
  fi
}

# Build a temp dir holding a mock `gh`. The mock emits PR metadata JSON for
# `gh pr view ... --json labels,title,url` and a newline path list for
# `gh pr diff ... --name-only`, both driven by MOCK_* env.
_mkbin() {
  local d
  d=$(mktemp -d)
  cat > "$d/gh" <<'GH'
#!/usr/bin/env bash
sub="$2"
if [[ "$sub" == "view" ]]; then
  [[ "${MOCK_FAIL_VIEW:-}" == "1" ]] && { echo "gh: view failed" >&2; exit 1; }
  labels_json=$(awk -v s="${MOCK_LABELS:-}" 'BEGIN{
    n=split(s,a,","); printf "["; p=0;
    for(i=1;i<=n;i++){ if(a[i]!=""){ if(p)printf ","; printf "{\"name\":\"%s\"}",a[i]; p=1 } }
    printf "]" }')
  printf '{"labels":%s,"title":"%s","url":"https://github.com/x/y/pull/123"}\n' \
    "$labels_json" "${MOCK_TITLE:-}"
  exit 0
fi
if [[ "$sub" == "diff" ]]; then
  [[ "${MOCK_FAIL_DIFF:-}" == "1" ]] && { echo "gh: diff failed" >&2; exit 1; }
  printf '%s\n' "${MOCK_FILES:-}"
  exit 0
fi
exit 2
GH
  chmod +x "$d/gh"
  echo "$d"
}

RUN_RC=0
RUN_OUT=""
# _run <title> <labels-csv> <files-newline> [fail_view] [fail_diff]
_run() {
  local title="$1" labels="$2" files="$3" fail_view="${4:-}" fail_diff="${5:-}"
  local bindir
  bindir=$(_mkbin)
  RUN_RC=0
  RUN_OUT=$(PATH="$bindir:$PATH" MOCK_TITLE="$title" MOCK_LABELS="$labels" \
    MOCK_FILES="$files" MOCK_FAIL_VIEW="$fail_view" MOCK_FAIL_DIFF="$fail_diff" \
    bash "$SCRIPT" 123 2>&1) || RUN_RC=$?
  rm -rf "$bindir"
}

_expect_eligible() {
  local label="$1" title="$2" labels="$3" files="$4"
  _run "$title" "$labels" "$files"
  if [[ "$RUN_RC" == "0" && "$RUN_OUT" == *eligible* && "$RUN_OUT" != *excluded* ]]; then
    _report "$label" ok
  else
    _report "$label" fail "rc=$RUN_RC out='$RUN_OUT'"
  fi
}

_expect_excluded() {
  local label="$1" title="$2" labels="$3" files="$4" fv="${5:-}" fd="${6:-}"
  _run "$title" "$labels" "$files" "$fv" "$fd"
  if [[ "$RUN_RC" != "0" && "$RUN_OUT" == *excluded* ]]; then
    _report "$label" ok
  else
    _report "$label" fail "rc=$RUN_RC out='$RUN_OUT'"
  fi
}

UI_FILES=$'apps/web-platform/app/(dashboard)/page.tsx\napps/web-platform/components/sidebar.tsx'

# --- Happy path ---
_expect_eligible "eligible: feat( + app:web-platform + UI paths" \
  "feat(web): float the sidebar collapse toggle" "semver:patch,app:web-platform" "$UI_FILES"

_expect_eligible "eligible: feat: (colon form) + app:web-platform" \
  "feat: add export button" "app:web-platform" "$UI_FILES"

# --- Deny labels (each alone, with otherwise-eligible PR) ---
_expect_excluded "deny label: type/security" \
  "feat(web): x" "app:web-platform,type/security" "$UI_FILES"
_expect_excluded "deny label: security/leak-suspected" \
  "feat(web): x" "app:web-platform,security/leak-suspected" "$UI_FILES"
_expect_excluded "deny label: infra-drift" \
  "feat(web): x" "app:web-platform,infra-drift" "$UI_FILES"
_expect_excluded "deny label: no-auto-ship" \
  "feat(web): x" "app:web-platform,no-auto-ship" "$UI_FILES"

# --- Deny paths (each alone) ---
_expect_excluded "deny path: migrations" \
  "feat(web): x" "app:web-platform" "apps/web-platform/supabase/migrations/099_x.sql"
_expect_excluded "deny path: (auth) route group" \
  "feat(web): x" "app:web-platform" "apps/web-platform/app/(auth)/login/page.tsx"
_expect_excluded "deny path: auth lib file" \
  "feat(web): x" "app:web-platform" "apps/web-platform/lib/auth.ts"
_expect_excluded "deny path: .github CI" \
  "feat(web): x" "app:web-platform" ".github/workflows/deploy.yml"
_expect_excluded "deny path: terraform .tf" \
  "feat(web): x" "app:web-platform" "apps/web-platform/infra/main.tf"
_expect_excluded "deny path: secrets/doppler" \
  "feat(web): x" "app:web-platform" "apps/web-platform/lib/doppler.ts"
_expect_excluded "deny path: .env" \
  "feat(web): x" "app:web-platform" "apps/web-platform/.env.example"
# Infra/credential/payment surfaces added after #5017 review (security-sentinel
# + user-impact-reviewer): these forbidden shapes previously reached `eligible`.
_expect_excluded "deny path: vercel.json deploy manifest" \
  "feat(web): x" "app:web-platform" "vercel.json"
_expect_excluded "deny path: k8s manifest" \
  "feat(web): x" "app:web-platform" "k8s/deployment.yaml"
_expect_excluded "deny path: helm chart" \
  "feat(web): x" "app:web-platform" "charts/web/values.yaml"
_expect_excluded "deny path: docker-compose" \
  "feat(web): x" "app:web-platform" "docker-compose.yml"
_expect_excluded "deny path: Next.js middleware (auth chokepoint)" \
  "feat(web): x" "app:web-platform" "apps/web-platform/middleware.ts"
_expect_excluded "deny path: Makefile" \
  "feat(web): x" "app:web-platform" "Makefile"
_expect_excluded "deny path: deploy script" \
  "feat(web): x" "app:web-platform" "scripts/deploy-prod.sh"
_expect_excluded "deny path: supabase config" \
  "feat(web): x" "app:web-platform" "apps/web-platform/supabase/config.toml"
_expect_excluded "deny path: supabase edge function" \
  "feat(web): x" "app:web-platform" "apps/web-platform/supabase/functions/handler.ts"
_expect_excluded "deny path: billing surface" \
  "feat(web): x" "app:web-platform" "apps/web-platform/app/api/billing/route.ts"
_expect_excluded "deny path: stripe lib" \
  "feat(web): x" "app:web-platform" "apps/web-platform/lib/stripe.ts"
_expect_excluded "deny path: payment surface" \
  "feat(web): x" "app:web-platform" "apps/web-platform/components/payment-form.tsx"
_expect_excluded "deny path: oauth flow" \
  "feat(web): x" "app:web-platform" "apps/web-platform/lib/oauth-token-injection.ts"
_expect_excluded "deny path: api-keys surface" \
  "feat(web): x" "app:web-platform" "apps/web-platform/app/api/api-keys/route.ts"
# A "stripe" / "payment" substring inside a benign path must NOT over-match
# (anchored at a path-segment boundary).
_expect_eligible "eligible: 'pinstripe' substring does not trip stripe deny" \
  "feat(web): pinstripe theme" "app:web-platform" "apps/web-platform/components/pinstripe-theme.tsx"

# --- Collisions: deny short-circuits regardless of allow-set ---
_expect_excluded "collision: feat(+app:web-platform+type/security -> excluded" \
  "feat(web): security hardening with UI" "app:web-platform,type/security" "$UI_FILES"
_expect_excluded "collision: feat(+app:web-platform + migrations path -> excluded" \
  "feat(web): new dashboard backed by migration" "app:web-platform" \
  $'apps/web-platform/app/(dashboard)/page.tsx\napps/web-platform/supabase/migrations/100_x.sql'

# --- Missing allow signal ---
_expect_excluded "excluded: missing app:web-platform label" \
  "feat(web): x" "semver:patch" "$UI_FILES"
_expect_excluded "excluded: non-feat title (fix)" \
  "fix(web): patch a bug" "app:web-platform" "$UI_FILES"
_expect_excluded "excluded: unlabeled PR" \
  "feat(web): x" "" "$UI_FILES"

# --- gh errors / fail-closed ---
_expect_excluded "excluded: gh pr view error" \
  "feat(web): x" "app:web-platform" "$UI_FILES" "1" ""
_expect_excluded "excluded: gh pr diff error" \
  "feat(web): x" "app:web-platform" "$UI_FILES" "" "1"
_expect_excluded "excluded: empty PR title" \
  "" "app:web-platform" "$UI_FILES"
# Empty changed-file list (gh anomaly) must fail closed — it would otherwise
# disable the entire deny-path layer (#5017 review: security + user-impact).
_expect_excluded "excluded: empty changed-file list (fail-closed)" \
  "feat(web): x" "app:web-platform" ""

echo "=== tweet-eligibility: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
