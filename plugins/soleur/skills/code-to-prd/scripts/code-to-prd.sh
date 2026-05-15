#!/usr/bin/env bash
# code-to-prd: reverse-engineer a Next.js codebase into a PRD (#2726).
#
# Single-script implementation per Simplicity review: walker + framework
# detection + extraction + render + 3-layer fail-closed redaction
# orchestration. v1 = Next.js only (App Router + Pages Router).
#
# Usage:
#   bash code-to-prd.sh <target-codebase-path> [<output-path>]
#
# If <output-path> is omitted, defaults to
# `knowledge-base/product/prd/<package-name>-prd.md` resolved relative to the
# repo root containing this script.
#
# Exit codes:
#   0 — PRD written successfully (or degraded-success path per FR8.1)
#   1 — redaction sentinel halted the write (Layer 2 or Layer 3)
#   2 — preflight failed (gitleaks missing, no package.json, empty walker,
#       not Next.js, target unreadable, etc.)
#   3 — IO error or write-deletion failure (loud operator message)
#
# Env knobs (test-only — never used in normal operation):
#   CODE_TO_PRD_SKIP_LAYER_2=1 — bypass Layer 2 sentinel (AC5 RED test).
#   CODE_TO_PRD_FAKE_SFA_FAIL=1 — force the SKIPPED gap-analysis placeholder
#       (degraded-success path, FR8.1 / AC7). No-op in default flow because
#       v1 always writes the SKIPPED placeholder — operator runs
#       spec-flow-analyzer via Task to populate it afterward.

set -uo pipefail

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_DIR="$(cd "${SKILL_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

REDACT_SENTINEL="${PLUGIN_DIR}/skills/incident/scripts/redact-sentinel.sh"
BANNER_TEMPLATE="${SKILL_DIR}/references/banner-template.md"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: code-to-prd.sh <target-codebase-path> [<output-path>]" >&2
  exit 2
fi

TARGET="$1"
OUTPUT_OVERRIDE="${2:-}"

# ---------------------------------------------------------------------------
# Phase 0 preflight (FR6.2 + FR1.1)
# ---------------------------------------------------------------------------
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "code-to-prd: gitleaks not found on PATH; install via 'brew install gitleaks' or equivalent." >&2
  echo "  Layer 3 verifier is mandatory (single-user incident threshold)." >&2
  exit 2
fi

if [[ ! -d "${TARGET}" ]]; then
  echo "code-to-prd: target directory does not exist: ${TARGET}" >&2
  exit 2
fi

TARGET_ABS="$(cd "${TARGET}" && pwd)"

if [[ ! -f "${TARGET_ABS}/package.json" ]]; then
  echo "code-to-prd: no package.json at target root: ${TARGET_ABS}/package.json" >&2
  exit 2
fi

if [[ ! -r "${REDACT_SENTINEL}" ]]; then
  echo "code-to-prd: incident/scripts/redact-sentinel.sh missing or not readable." >&2
  echo "  expected at: ${REDACT_SENTINEL}" >&2
  exit 2
fi

if [[ ! -r "${BANNER_TEMPLATE}" ]]; then
  echo "code-to-prd: banner-template.md missing at ${BANNER_TEMPLATE}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Framework detection — Next.js required (FR1)
# ---------------------------------------------------------------------------
NEXT_CONFIG=""
for ext in js ts mjs cjs; do
  candidate="${TARGET_ABS}/next.config.${ext}"
  if [[ -f "${candidate}" ]]; then
    NEXT_CONFIG="${candidate}"
    break
  fi
done

if [[ -z "${NEXT_CONFIG}" ]]; then
  echo "code-to-prd: framework detection failed — no next.config.{js,ts,mjs,cjs} at ${TARGET_ABS}" >&2
  echo "  v1 supports Next.js only. Rails/Django are tracked for v2 (#2726 deferrals)." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Walker — git ls-files honors .gitignore (FR2) + path filter (Layer 1) +
# realpath symlink rejection (FR2.1)
# ---------------------------------------------------------------------------
if ! git -C "${TARGET_ABS}" rev-parse --git-dir >/dev/null 2>&1; then
  # Not a git repo — fall back to find, but the fixture and production targets
  # are expected to be under git. Empty fallback list triggers FR1.1 below.
  RAW_FILES=""
else
  RAW_FILES="$(git -C "${TARGET_ABS}" ls-files -c -o --exclude-standard 2>/dev/null || true)"
fi

# FR1.1: empty walker means the target is a directory but tracks nothing.
if [[ -z "${RAW_FILES}" ]]; then
  echo "code-to-prd: walker returned 0 files for ${TARGET_ABS} — target must be under git with tracked files." >&2
  echo "  Monorepo support deferred to v2; v1 scopes to the directory containing the first package.json." >&2
  exit 2
fi

# Layer 1 — path-exclusion filter
is_excluded() {
  local p="$1"
  case "${p}" in
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
    secrets.*|*/secrets.*) return 0 ;;
    *.pem|*.key) return 0 ;;
    credentials.*|*/credentials.*) return 0 ;;
    master.key|*/master.key) return 0 ;;
    .git/*|*/.git/*) return 0 ;;
  esac
  return 1
}

# FR2.1: resolve each candidate via realpath and reject anything that
# escapes <target> (planted symlinks in inherited-prototype threat model).
declare -a FILES
declare -a EXCLUDED_FILES
EXCLUDED_BY_FILTER=0
EXCLUDED_BY_SYMLINK=0
while IFS= read -r rel; do
  [[ -z "${rel}" ]] && continue
  full="${TARGET_ABS}/${rel}"
  if [[ ! -e "${full}" ]]; then
    continue
  fi
  # Reject symlinks outright (v1 stance).
  if [[ -L "${full}" ]]; then
    EXCLUDED_BY_SYMLINK=$((EXCLUDED_BY_SYMLINK + 1))
    continue
  fi
  resolved="$(realpath --relative-base="${TARGET_ABS}" "${full}" 2>/dev/null || echo "${full}")"
  # Anything starting with `/` or `../` escaped the target root.
  case "${resolved}" in
    /*|../*)
      EXCLUDED_BY_SYMLINK=$((EXCLUDED_BY_SYMLINK + 1))
      continue
      ;;
  esac
  if is_excluded "${rel}"; then
    EXCLUDED_BY_FILTER=$((EXCLUDED_BY_FILTER + 1))
    EXCLUDED_FILES+=("${rel}")
    continue
  fi
  FILES+=("${rel}")
done <<< "${RAW_FILES}"

WALKER_COUNT=${#FILES[@]}
EXCLUDED_TOTAL=$((EXCLUDED_BY_FILTER + EXCLUDED_BY_SYMLINK))

if (( WALKER_COUNT == 0 )); then
  echo "code-to-prd: walker emitted no eligible files after path-exclusion filter." >&2
  echo "  excluded by filter: ${EXCLUDED_BY_FILTER}; excluded as symlink: ${EXCLUDED_BY_SYMLINK}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Helpers — project name + output path
# ---------------------------------------------------------------------------
extract_package_name() {
  # Best-effort: grep the first `"name": "..."` line. Sanitization to kebab-case
  # handles scoped packages (`@org/pkg` → `org-pkg`).
  awk '
    /"name"[[:space:]]*:/ {
      match($0, /"name"[[:space:]]*:[[:space:]]*"([^"]+)"/, a)
      if (a[1] != "") { print a[1]; exit }
    }
  ' "${TARGET_ABS}/package.json" 2>/dev/null
}

kebab_case() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's|@||g; s|/|-|g; s|[^a-z0-9-]+|-|g; s|^-+||; s|-+$||'
}

PROJECT_NAME_RAW="$(extract_package_name)"
PROJECT_NAME="$(kebab_case "${PROJECT_NAME_RAW:-unnamed-next-project}")"
[[ -z "${PROJECT_NAME}" ]] && PROJECT_NAME="unnamed-next-project"

if [[ -n "${OUTPUT_OVERRIDE}" ]]; then
  OUTPUT_PATH="${OUTPUT_OVERRIDE}"
else
  OUTPUT_PATH="${REPO_ROOT}/knowledge-base/product/prd/${PROJECT_NAME}-prd.md"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

# ---------------------------------------------------------------------------
# Extraction helpers (regex-only; v1 has no AST analysis — see Coverage Caveats)
# ---------------------------------------------------------------------------
file_in_target() { printf '%s' "${TARGET_ABS}/$1"; }

# Filter FILES[] by extension/path-pattern.
filter_files() {
  local pattern="$1"
  local f
  for f in "${FILES[@]}"; do
    if [[ "${f}" =~ ${pattern} ]]; then
      printf '%s\n' "${f}"
    fi
  done
}

# Extract first JSDoc/TSDoc one-liner above the default export — best effort.
first_jsdoc() {
  local file="$1"
  awk '
    /^\/\*\*/ { in_block=1; buf=""; next }
    in_block && /^[[:space:]]*\*\// { in_block=0; print buf; exit }
    in_block {
      line=$0
      sub(/^[[:space:]]*\*[[:space:]]?/, "", line)
      if (line != "" && buf == "") { buf = line }
    }
  ' "${file}" 2>/dev/null | head -1
}

# Extract HTTP methods exported from a route handler (named exports).
route_methods() {
  local file="$1"
  grep -oE 'export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b' "${file}" 2>/dev/null \
    | awk '{print $NF}' \
    | sort -u \
    | paste -sd, -
}

# Path → route (App Router): app/foo/bar/page.tsx → /foo/bar
app_route_from_path() {
  local p="$1"
  p="${p#app/}"
  p="${p%/page.*}"
  p="${p%/route.*}"
  if [[ "${p}" == "page."* || "${p}" == "route."* ]]; then
    echo "/"
  else
    echo "/${p}"
  fi
}

# Path → route (Pages Router): pages/foo/bar.tsx → /foo/bar; index → /
pages_route_from_path() {
  local p="$1"
  p="${p#pages/}"
  p="${p%.tsx}"; p="${p%.ts}"; p="${p%.jsx}"; p="${p%.js}"
  p="${p%/index}"
  if [[ "${p}" == "index" ]]; then
    echo "/"
  else
    echo "/${p}"
  fi
}

# ---------------------------------------------------------------------------
# Section renderers — emit to stdout, captured by the orchestrator below
# ---------------------------------------------------------------------------
render_routes() {
  echo "## Routes"
  echo ""
  echo "### App Router"
  echo ""
  local app_pages=() app_handlers=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && app_pages+=("${f}")
  done < <(filter_files '^app/.*page\.(tsx|jsx|ts|js)$')
  while IFS= read -r f; do
    [[ -n "${f}" ]] && app_handlers+=("${f}")
  done < <(filter_files '^app/.*route\.(ts|js)$')

  if (( ${#app_pages[@]} == 0 && ${#app_handlers[@]} == 0 )); then
    echo "_No App Router routes detected._"
    echo ""
  else
    echo "| Route | File | Methods | Description |"
    echo "|---|---|---|---|"
    local f route desc methods
    for f in "${app_pages[@]}"; do
      route="$(app_route_from_path "${f}")"
      desc="$(first_jsdoc "$(file_in_target "${f}")")"
      desc="${desc:-—}"
      printf '| `%s` | `%s` | page | %s |\n' "${route}" "${f}" "${desc}"
    done
    for f in "${app_handlers[@]}"; do
      route="$(app_route_from_path "${f}")"
      methods="$(route_methods "$(file_in_target "${f}")")"
      methods="${methods:-?}"
      desc="$(first_jsdoc "$(file_in_target "${f}")")"
      desc="${desc:-—}"
      printf '| `%s` | `%s` | %s | %s |\n' "${route}" "${f}" "${methods}" "${desc}"
    done
    echo ""
  fi

  echo "### Pages Router"
  echo ""
  local pages_routes=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && pages_routes+=("${f}")
  done < <(filter_files '^pages/[^_].*\.(tsx|jsx|ts|js)$')

  if (( ${#pages_routes[@]} == 0 )); then
    echo "_No Pages Router routes detected._"
    echo ""
  else
    echo "| Route | File | Description |"
    echo "|---|---|---|"
    local f route desc
    for f in "${pages_routes[@]}"; do
      route="$(pages_route_from_path "${f}")"
      desc="$(first_jsdoc "$(file_in_target "${f}")")"
      desc="${desc:-—}"
      printf '| `%s` | `%s` | %s |\n' "${route}" "${f}" "${desc}"
    done
    echo ""
  fi
}

render_state_shapes() {
  echo "## State Shapes"
  echo ""
  echo "Regex-derived snapshot of client-state hooks across tracked files. Best-effort; see Coverage Caveats."
  echo ""
  local count=0
  local f
  for f in "${FILES[@]}"; do
    [[ "${f}" =~ \.(tsx|jsx|ts|js)$ ]] || continue
    local full
    full="$(file_in_target "${f}")"
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      printf -- '- `%s` — `%s`\n' "${f}" "${line}"
      count=$((count + 1))
    done < <(grep -nE '\buse(State|Reducer)\b\s*[(<]' "${full}" 2>/dev/null | head -3)
  done
  if (( count == 0 )); then
    echo "_No `useState`/`useReducer` call sites detected._"
  fi
  echo ""
}

render_api_deps() {
  echo "## API & External Dependencies"
  echo ""
  echo "### fetch() literal URLs"
  echo ""
  local hits
  hits="$(
    for f in "${FILES[@]}"; do
      [[ "${f}" =~ \.(tsx|jsx|ts|js|mjs|cjs)$ ]] || continue
      grep -hEo "fetch\(['\"][^'\"]+['\"]" "$(file_in_target "${f}")" 2>/dev/null \
        | sed -E "s/^fetch\(['\"]//; s/['\"]\$//"
    done | sort -u
  )"
  if [[ -z "${hits}" ]]; then
    echo "_None detected._"
  else
    while IFS= read -r u; do
      [[ -z "${u}" ]] && continue
      printf -- '- `%s`\n' "${u}"
    done <<< "${hits}"
  fi
  echo ""

  echo "### Internal API imports"
  echo ""
  hits="$(
    for f in "${FILES[@]}"; do
      [[ "${f}" =~ \.(tsx|jsx|ts|js|mjs|cjs)$ ]] || continue
      grep -hEo "from[[:space:]]+['\"]@/(lib/api[^'\"]*|server/[^'\"]*)['\"]" "$(file_in_target "${f}")" 2>/dev/null \
        | sed -E "s/^from[[:space:]]+['\"]//; s/['\"]\$//"
    done | sort -u
  )"
  if [[ -z "${hits}" ]]; then
    echo "_None detected._"
  else
    while IFS= read -r u; do
      [[ -z "${u}" ]] && continue
      printf -- '- `%s`\n' "${u}"
    done <<< "${hits}"
  fi
  echo ""

  echo "### Environment-variable names (FR5 — values never read)"
  echo ""
  hits="$(
    for f in "${FILES[@]}"; do
      [[ "${f}" =~ \.(tsx|jsx|ts|js|mjs|cjs)$ ]] || continue
      grep -hEo 'process\.env\.[A-Z_][A-Z0-9_]*' "$(file_in_target "${f}")" 2>/dev/null \
        | sed -E 's/^process\.env\.//'
    done | sort -u
  )"
  if [[ -z "${hits}" ]]; then
    echo "_None detected._"
  else
    while IFS= read -r u; do
      [[ -z "${u}" ]] && continue
      printf -- '- `%s`\n' "${u}"
    done <<< "${hits}"
  fi
  echo ""

  echo "### Third-party SDK packages (from package.json)"
  echo ""
  hits="$(
    awk '
      /"(dependencies|peerDependencies|devDependencies)"[[:space:]]*:/ { in_deps=1; depth=0; next }
      in_deps && /\{/ { depth++ }
      in_deps && /\}/ { depth--; if (depth <= 0) { in_deps=0; depth=0; next } }
      in_deps {
        if (match($0, /"([^"]+)"[[:space:]]*:[[:space:]]*"/, a)) {
          print a[1]
        }
      }
    ' "${TARGET_ABS}/package.json" 2>/dev/null | sort -u
  )"
  if [[ -z "${hits}" ]]; then
    echo "_None detected._"
  else
    while IFS= read -r u; do
      [[ -z "${u}" ]] && continue
      printf -- '- `%s`\n' "${u}"
    done <<< "${hits}"
  fi
  echo ""
}

render_coverage_caveats() {
  echo "## Coverage Caveats"
  echo ""
  echo "### Frameworks not scanned"
  echo ""
  echo "v1 detects Next.js only. The following frameworks are NOT scanned by this run: Rails, Django, FastAPI, Express, NestJS, Remix, Astro, SvelteKit, Nuxt, Phoenix. If the target codebase mixes Next.js with one of these, the non-Next.js surface is invisible to this PRD."
  echo ""
  echo "### Extraction techniques used"
  echo ""
  echo "- Filesystem walk via \`git ls-files -c -o --exclude-standard\` (honors \`.gitignore\`)."
  echo "- Regex on source — no AST analysis. Estimated false-negative rate: ~30% on dynamic imports, computed routes, conditional renders."
  echo "- One-line JSDoc/TSDoc extraction from the first \`/** … */\` block in each route file."
  echo "- HTTP method detection via \`export (async )?function (GET|POST|…)\` regex; arrow-function exports are NOT detected."
  echo ""
  echo "### Excluded by path filter"
  echo ""
  echo "${EXCLUDED_BY_FILTER} files excluded by Layer 1 path filter (categories: \`.env*\`, \`secrets.*\`, \`*.pem\`, \`*.key\`, \`credentials.*\`, \`master.key\`, \`.git/**\`). ${EXCLUDED_BY_SYMLINK} files excluded as symlinks (FR2.1 — inherited-prototype threat model). Exact paths are intentionally omitted to avoid recreating the redaction surface."
  echo ""
  echo "### GDPR Art. 9 special-category disclaimer"
  echo ""
  echo "Automated redaction (\`redact-sentinel.sh\` + \`gitleaks\`) covers 14 secret/PII classes (JWT, email, UUID, Stripe/GitHub/Anthropic/OpenAI/Supabase keys, IPv4, env-var values, PEM private keys). It does **NOT** detect Article 9 special-category text content (race, ethnicity, religion, political views, health, biometric, sexual orientation). Before sharing this PRD outside the founder's immediate trust circle, review banner-flagged sections and any free-text content for Art. 9 categories. See \`knowledge-base/project/learnings/2026-05-15-fail-closed-redaction-enables-committed-default-output.md\` for the v2 keyword-scan layer roadmap."
  echo ""
}

render_gap_analysis_placeholder() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "## Gap Analysis"
  echo ""
  echo "SKIPPED (spec-flow-analyzer unavailable at ${ts})"
  echo ""
  echo "_Per FR8.1 degraded-success — operator may invoke \`@agent-soleur:product:spec-flow-analyzer\` via Task on this PRD path to populate this section. The placeholder is the default state because the bash script cannot directly spawn Claude Code agents (v1 limitation, tracked for v2)._"
  echo ""
}

# ---------------------------------------------------------------------------
# Orchestrator — render to a temp file, run Layer 2, write to disk, run Layer 3
# ---------------------------------------------------------------------------
STAGING="$(mktemp -t code-to-prd.XXXXXX.md)"
cleanup() {
  [[ -e "${STAGING}" ]] && rm -f "${STAGING}"
}
trap cleanup EXIT INT TERM HUP

GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

{
  echo "---"
  echo "project: \"${PROJECT_NAME}\""
  echo "framework: \"next.js\""
  echo "generator: \"code-to-prd@v1\""
  echo "generated_at: \"${GENERATED_AT}\""
  echo "walker_count: ${WALKER_COUNT}"
  echo "walker_excluded: ${EXCLUDED_TOTAL}"
  echo "---"
  echo ""
  echo "# PRD — ${PROJECT_NAME}"
  echo ""
  cat "${BANNER_TEMPLATE}"
  echo ""
  echo "## Overview"
  echo ""
  echo "- **Project name:** \`${PROJECT_NAME}\` (from \`package.json\`)."
  echo "- **Framework:** Next.js (\`${NEXT_CONFIG##*/}\` detected)."
  echo "- **Walker stats:** ${WALKER_COUNT} tracked files scanned; ${EXCLUDED_TOTAL} excluded by Layer 1 + symlink rejection."
  echo "- **Generator:** \`code-to-prd@v1\` — see \`plugins/soleur/skills/code-to-prd/SKILL.md\`."
  echo ""
  render_routes
  render_state_shapes
  render_api_deps
  render_coverage_caveats
  render_gap_analysis_placeholder
  echo "---"
  echo ""
  echo "_Adapted from \`alirezarezvani/claude-skills\` (MIT) — see [plugins/soleur/NOTICE](../../../plugins/soleur/NOTICE)._"
} > "${STAGING}"

# ---------------------------------------------------------------------------
# Layer 2 — pre-write sentinel (fail-closed)
# ---------------------------------------------------------------------------
if [[ "${CODE_TO_PRD_SKIP_LAYER_2:-0}" != "1" ]]; then
  if ! bash "${REDACT_SENTINEL}" "${STAGING}" >/dev/null 2>&1; then
    sentinel_rc=$?
    if (( sentinel_rc == 1 )); then
      echo "code-to-prd: Layer 2 sentinel found redaction-class matches in the rendered PRD." >&2
      echo "  Aborting write — no partial PRD lands on disk." >&2
      echo "  Run \`bash ${REDACT_SENTINEL} <staging>\` against a debug copy to see the matched classes." >&2
      exit 1
    elif (( sentinel_rc == 2 )); then
      echo "code-to-prd: Layer 2 sentinel invocation failed (exit 2). Investigate before retrying." >&2
      exit 1
    else
      echo "code-to-prd: Layer 2 sentinel returned unexpected exit ${sentinel_rc}." >&2
      exit 1
    fi
  fi
else
  echo "code-to-prd: WARNING — CODE_TO_PRD_SKIP_LAYER_2=1 is set; bypassing Layer 2 (test-only path)." >&2
fi

# Write to disk.
if ! cp "${STAGING}" "${OUTPUT_PATH}"; then
  echo "code-to-prd: failed to write PRD to ${OUTPUT_PATH}" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Layer 3 — post-write gitleaks verifier (fail-closed)
# ---------------------------------------------------------------------------
GITLEAKS_OUT="$(mktemp -t code-to-prd-gl.XXXXXX.json)"
trap 'cleanup; [[ -e "${GITLEAKS_OUT}" ]] && rm -f "${GITLEAKS_OUT}"' EXIT INT TERM HUP

if ! gitleaks detect \
    --source "${OUTPUT_PATH}" \
    --no-git \
    --report-format json \
    --report-path "${GITLEAKS_OUT}" \
    --redact \
    --exit-code 1 \
    >/dev/null 2>&1; then
  # Non-zero exit from gitleaks = findings (per --exit-code 1). Delete + verify.
  rm -f "${OUTPUT_PATH}"
  if [[ -e "${OUTPUT_PATH}" ]]; then
    echo "code-to-prd: CRITICAL — Layer 3 found secrets but delete failed at ${OUTPUT_PATH}" >&2
    echo "  Manually remove this file BEFORE committing or sharing." >&2
    exit 3
  fi
  echo "code-to-prd: Layer 3 (gitleaks) found secrets in the written PRD; file deleted." >&2
  echo "  Report at: ${GITLEAKS_OUT}" >&2
  exit 1
fi

echo "code-to-prd: wrote ${OUTPUT_PATH}"
echo "  walker: ${WALKER_COUNT} files | excluded: ${EXCLUDED_TOTAL}"
echo "  Next step: invoke @agent-soleur:product:spec-flow-analyzer via Task to populate Gap Analysis."
exit 0
