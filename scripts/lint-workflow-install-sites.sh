#!/usr/bin/env bash
# Guard 2 — install sites resolve through npm, with scripts disabled.
#
# Three clauses, deliberately separated because their scopes differ:
#   1. No install step over a `package-lock.json` directory runs `bun install`.
#   2. Every install step over such a directory runs `npm ci --ignore-scripts`.
#   3. Any step invoking `bun ` is preceded by a `setup-bun` step in the same job.
#
# Clause 2 covers the four pre-existing bare `npm ci` sites too, and that is not tidiness:
# `ci.yml` triggers on `pull_request`, a fork PR controls `apps/web-platform/package.json`,
# so `web-platform-build` already executes every `hasInstallScript` package — including
# @sentry/cli's network binary download — on untrusted code today. Clause 3 is what makes
# Phase 2.5's by-hand `setup-bun` removals safe rather than a judgment call.
#
# ASSEMBLY — three location classes, enumerated from `git ls-files`, not one glob:
#   1. every *.yml under ANY `.github/workflows/` path, repo-root AND nested. A repo-root
#      glob provably misses apps/web-platform/.github/workflows/constraint-gates.yml, a
#      live install site byte-parity-diffed against two siblings.
#   2. scripts/**/*.sh and plugins/**/*.sh — plugins/soleur/scripts/grok-fidelity-gate.sh
#      is a live install site feeding the REQUIRED grok-fidelity check.
#   3. constraint-scaffold/references/*.template — emitted workflows that parity.test.sh
#      byte-diffs against class 1.
# A `.github/workflows/*.yml`-only assembly was this guard's original shape and would have
# reported GREEN with two live `bun install` sites remaining — the exact false-green it
# exists to prevent.
#
# The scan classifies by `run:` COMMAND, not by raw string: `git grep -n 'bun install'`
# over the workflow directory returns far more lines than there are invocations (comments,
# ::error:: strings, prose). Matching the raw string would fire on a correct tree, and a
# false-RED guard gets disabled.
#
# BOUNDARY (asserted by H3, not merely described). OUT OF SCOPE:
#   - composite actions under `.github/actions/**`;
#   - the production Dockerfile, which deliberately runs `npm ci` WITHOUT --ignore-scripts;
#   - `apps/web-platform/scripts/*-in-image.sh`, which install inside an image build against
#     a pinned SDK — same class as the Dockerfile, and named here rather than left as a
#     silent gap in the class-2 globs;
#   - `*.test.sh`, because a mutation battery's heredoc FIXTURES necessarily contain the
#     exact violating text the guard looks for. Without this, the guard reddens on its own
#     test suite: a false positive that would get the guard disabled, which is the failure
#     mode clause 1's invocation-vs-raw-string discrimination exists to avoid.
# The `*.test.sh` exclusion is a real (accepted) hole: a test script performing a genuine
# install is unseen. It is the narrowest exclusion that keeps the guard credible.
#
# Two anti-vacuity floors, because file enumeration and step extraction fail independently:
# a broken step regex would scan every workflow, match nothing, and exit 0 green — the
# file-count floor cannot see that.
#
# ADR-191. Registered in scripts/test-all.sh via lint-workflow-install-sites.test.sh.
set -euo pipefail

MIN_WORKFLOW_FILES=40 # 74 today; mirrors the actionlint hang guard.
MIN_INSTALL_STEPS=20  # 16 converted bun sites + 4 pre-existing npm sites.

root=$(git rev-parse --show-toplevel)
cd "$root"

failures=0
fail() {
  echo "::error::lint-workflow-install-sites: $*" >&2
  failures=$((failures + 1))
}

mapfile -t tracked < <(git ls-files)
if [[ ${#tracked[@]} -eq 0 ]]; then
  echo "::error::lint-workflow-install-sites: git ls-files returned nothing — enumeration is broken, not clean." >&2
  exit 1
fi

workflow_files=()
script_files=()
template_files=()
for f in "${tracked[@]}"; do
  case "$f" in
    .github/actions/*) continue ;; # stated boundary
    *.github/workflows/*.yml | *.github/workflows/*.yaml) workflow_files+=("$f") ;;
    *.test.sh) continue ;; # stated boundary: harness fixtures carry violating text by design
    # A `case` glob's `*` matches `/` (unlike pathname expansion), so these two patterns
    # already cover arbitrary depth. The per-depth alternatives that used to sit here were
    # dead weight, and shellcheck flagged them (SC2221/SC2222) precisely because the first
    # one subsumes them all.
    scripts/*.sh | plugins/*.sh)
      script_files+=("$f")
      ;;
    plugins/soleur/skills/constraint-scaffold/references/*.template) template_files+=("$f") ;;
  esac
done

# Extraction runs as ONE awk pass over the whole scanned set. A per-line bash function was
# the obvious shape and is unusable here: ~150k lines across ~500 files, and the repo
# contains a 4209-character workflow line that sends bash's `cd <path> &&` regex into
# catastrophic backtracking. awk compiles its patterns once and is linear.
#
# A line is an INVOCATION only after: ltrim, dropping a `- ` list marker, dropping a `run:`
# key (inline or block), rejecting comments and echo/::error:: strings, and stripping any
# `cd <path> &&` / `(cd <path> &&` prefix (form 4). That discrimination is the whole point —
# matching the raw string `bun install` fires on comments and log strings, i.e. on a
# CORRECT post-conversion tree, and a false-RED guard gets disabled.
extract_installs() {
  awk '
    {
      cmd = $0
      sub(/^[[:space:]]+/, "", cmd)
      if (cmd ~ /^#/) next
      sub(/^-[[:space:]]+/, "", cmd)
      sub(/^[[:space:]]+/, "", cmd)
      if (cmd ~ /^#/) next
      sub(/^run:[[:space:]]*\|?-?[[:space:]]*/, "", cmd)
      if (cmd ~ /^(echo|printf)[[:space:]]/) next
      if (cmd ~ /::(error|warning|notice)::/) next
      # Bounded loop: each iteration strips a `cd … &&`, so it always shortens.
      for (i = 0; i < 8; i++) {
        if (cmd ~ /^\(?cd[[:space:]]+[^&]+&&[[:space:]]*/) sub(/^\(?cd[[:space:]]+[^&]+&&[[:space:]]*/, "", cmd)
        else break
      }
      if (cmd ~ /^bun install/ || cmd ~ /^npm ci/) printf "%s\t%s\n", FILENAME, cmd
    }
  ' "$@"
}

install_steps=0
declare -a offending_bun=()
declare -a offending_scripts=()

while IFS=$'\t' read -r file cmd; do
  [[ -n "$file" ]] || continue
  install_steps=$((install_steps + 1))
  case "$cmd" in
    'bun install'*) offending_bun+=("${file}: ${cmd}") ;;
    'npm ci'*)
      if [[ "$cmd" != *--ignore-scripts* ]]; then
        offending_scripts+=("${file}: ${cmd}")
      fi
      ;;
  esac
done < <(extract_installs \
  ${workflow_files[@]+"${workflow_files[@]}"} \
  ${script_files[@]+"${script_files[@]}"} \
  ${template_files[@]+"${template_files[@]}"})

# --- Floors first: a zero-violation result is meaningless if the scan did not run. ---
if [[ ${#workflow_files[@]} -lt $MIN_WORKFLOW_FILES ]]; then
  fail "workflow enumeration found ${#workflow_files[@]} file(s), below the floor of ${MIN_WORKFLOW_FILES}. The glob is broken."
fi
if [[ $install_steps -lt $MIN_INSTALL_STEPS ]]; then
  fail "matched ${install_steps} install step(s), below the floor of ${MIN_INSTALL_STEPS}. The step-matching regex is broken — it scanned ${#workflow_files[@]} workflow file(s) and found almost nothing, which the file-count floor alone cannot detect."
fi

# --- Clause 1 ---
for hit in ${offending_bun[@]+"${offending_bun[@]}"}; do
  fail "installs with bun: ${hit}. Use 'npm ci --ignore-scripts' — npm is the single lockfile of record (ADR-191, #7084)."
done

# --- Clause 2 ---
for hit in ${offending_scripts[@]+"${offending_scripts[@]}"}; do
  fail "install step runs install scripts: ${hit}. Add --ignore-scripts. ci.yml triggers on pull_request and a fork PR controls package.json, so this executes untrusted install scripts."
done

# --- Clause 3: a step invoking `bun ` needs setup-bun in the SAME job. ---
for wf in ${workflow_files[@]+"${workflow_files[@]}"}; do
  while IFS=$'\t' read -r job uses_bun has_setup; do
    [[ -n "$job" ]] || continue
    if [[ "$uses_bun" == "1" && "$has_setup" == "0" ]]; then
      fail "${wf}: job '${job}' invokes bun but has no setup-bun step. Removing setup-bun from a job that still runs bun breaks it at run time."
    fi
  done < <(awk '
    /^jobs:[[:space:]]*$/ { injobs=1; next }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if (job != "") print job "\t" usesbun "\t" hassetup
      job = $1; sub(/:$/, "", job); usesbun = 0; hassetup = 0; next
    }
    injobs && /^[A-Za-z]/ {
      if (job != "") print job "\t" usesbun "\t" hassetup
      job = ""; injobs = 0; next
    }
    job != "" && /oven-sh\/setup-bun/ { hassetup = 1 }
    job != "" && /^[[:space:]]*(- )?run:.*(^|[[:space:]])bun[[:space:]]/ { usesbun = 1 }
    job != "" && /^[[:space:]]+bun[[:space:]]/ { usesbun = 1 }
    END { if (job != "") print job "\t" usesbun "\t" hassetup }
  ' "$wf")
done

echo "lint-workflow-install-sites: scanned ${#workflow_files[@]} workflow file(s) (floor ${MIN_WORKFLOW_FILES}), ${#script_files[@]} shell script(s), ${#template_files[@]} template(s); matched ${install_steps} install step(s) (floor ${MIN_INSTALL_STEPS})."

if [[ $failures -gt 0 ]]; then
  echo "::error::lint-workflow-install-sites: ${failures} violation(s)." >&2
  exit 1
fi
echo "lint-workflow-install-sites: OK"
